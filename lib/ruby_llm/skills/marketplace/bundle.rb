# frozen_string_literal: true

require "json"
require "yaml"
require "pathname"

module RubyLLM
  module Skills
    module Marketplace
      # One plugin's root tree, normalized into what the loaders read:
      # `skills/<name>/**` validated by the Agent Skills rules (frontmatter
      # `name` matches the directory, `description` present), `commands/*.md`
      # rewritten to `skills/<name>.md` (single-file skills), `agents/**/*.md`
      # kept verbatim, and plugin-level files a skill reaches through
      # `../../x` or `${CLAUDE_PLUGIN_ROOT}/x` copied under `<skill>/.plugin/`
      # with the reference rewritten. Hooks, MCP and LSP configuration,
      # executables and everything else are dropped. The tree's sha256 is the
      # plugin's integrity pin.
      #
      class Bundle
        MANIFEST_PATHS = %w[.claude-plugin/plugin.json .codex-plugin/plugin.json .cursor-plugin/plugin.json].freeze
        AGENT_PLUGINS_SCHEMA = "https://agent-plugins.org/schemas/"
        SUPPORT_ROOT = ".plugin"
        # Marketplace-entry display fields that win over plugin.json (Claude Code's rule).
        ENTRY_DISPLAY_FIELDS = %w[displayName description author homepage repository license keywords category tags].freeze
        ROOT_REFERENCE = %r{(?:\$\{(?:CLAUDE_)?PLUGIN_ROOT\}|<plugin-root>)/(\w[\w./-]*)}
        RELATIVE_REFERENCE = %r{(?<![\w./-])((?:\.\./)+\w[\w./-]*)}

        # One skill the plugin contributes; +kind+ is "skill" or "command".
        Skill = Data.define(:name, :description, :kind, :path, :frontmatter, :files) do
          def command? = kind == "command"

          # Where the skill lives in the normalized tree.
          def tree_path
            command? ? "skills/#{name}.md" : "skills/#{name}"
          end
        end

        # +files+ is the input tree as given (paths without a leading "./"); +tree+ the normalized output.
        attr_reader :files, :name, :manifest, :manifest_path, :manifest_version, :entry, :tree, :skills, :agents,
          :unsupported, :unresolved_references, :tree_sha256

        # @param files [Hash{String => String}] the plugin root as `{ path => bytes }`
        # @param entry [Manifest::Entry, nil] the marketplace entry, when there is one
        # @param plugin_name [String, nil] a name to use when neither manifest nor entry has one
        # @raise [InvalidPluginError]
        def initialize(files, entry: nil, plugin_name: nil)
          @files = files.transform_keys { |path| path.to_s.delete_prefix("./") }
          @entry = entry
          @manifest, @manifest_path, @manifest_version = discover_manifest
          @name = (plugin_name || entry&.name || manifest["name"]).to_s.strip
          raise InvalidPluginError, "plugin has no name (no manifest, no marketplace entry)" if @name.empty?
          raise InvalidPluginError, "plugin name #{@name.inspect} is not kebab-case" unless @name.match?(Manifest::NAME_PATTERN)

          @tree = {}
          @consumed = []
          @unsupported = []
          @unresolved_references = []
          @skills = collect_skills + collect_commands
          check_skill_names!
          @agents = collect_agents
          relocate_references
          @tree_sha256 = Tarball.tree_sha256(@tree)
        end

        # The plugin manifest's `version`, else the marketplace entry's, else nil.
        def version
          manifest_version || entry&.version
        end

        # "manifest" or "entry" when a version is declared, else nil.
        def version_kind
          return "manifest" if manifest_version
          "entry" if entry&.version
        end

        def display_name
          Manifest.presence(manifest["displayName"])
        end

        def description
          Manifest.presence(manifest["description"])
        end

        def skill_names
          skills.map(&:name)
        end

        # Nothing the loaders could serve.
        def empty?
          skills.empty? && agents.empty?
        end

        # Input paths that did not make it into the tree.
        def dropped
          @files.keys - @consumed
        end

        # Writes the tree under +dir+, replacing whatever was there.
        def write!(dir)
          FileUtils.rm_rf(dir)
          Tarball.write_directory(tree, dir)
        end

        private

        # --- manifest -----------------------------------------------------------

        # [manifest, path, version]: +version+ is the plugin manifest's own
        # (nil for a strict:false entry, whose version is the entry's).
        def discover_manifest
          if entry && !entry.strict?
            return [entry.raw.except("source", "strict").merge(entry.overrides), nil, nil]
          end

          root = json_file("plugin.json")
          data, path = if root.is_a?(Hash) && root["$schema"].to_s.start_with?(AGENT_PLUGINS_SCHEMA)
            [root, "plugin.json"]
          else
            found = MANIFEST_PATHS.find { |candidate| @files.key?(candidate) }
            [found ? json_file(found) : {}, found]
          end
          raise InvalidPluginError, "#{path} is not a JSON object" unless data.is_a?(Hash)

          [merge_entry(data), path, Manifest.presence(data["version"])]
        end

        def merge_entry(data)
          return data unless entry

          merged = data.merge(entry.raw.slice(*ENTRY_DISPLAY_FIELDS).reject { |_, value| blank?(value) })
          merged["version"] = Manifest.presence(data["version"]) || entry.version if Manifest.presence(data["version"]) || entry.version
          merged["skills"] = Array(data["skills"]) + Array(entry.overrides["skills"]) if entry.overrides.key?("skills")
          %w[commands agents].each { |key| merged[key] = entry.overrides[key] if entry.overrides.key?(key) }
          merged
        end

        def json_file(path)
          raw = @files[path]
          return nil if raw.nil?

          JSON.parse(text!(raw, path))
        rescue JSON::ParserError => e
          raise InvalidPluginError, "#{path} is not valid JSON (#{e.message[0, 60]})"
        end

        def text!(raw, path)
          text = raw.to_s.dup.force_encoding(Encoding::UTF_8)
          raise InvalidPluginError, "#{path} is not UTF-8 text" unless text.valid_encoding?

          text
        end

        # A manifest path ("./skills/", "./custom/x.md", ".") to tree-relative, or raises when it escapes.
        def manifest_paths(value)
          Array(value).filter_map do |raw|
            cleaned = Manifest.normalize_relative(raw.to_s, allow_blank: true)
            raise InvalidPluginError, "manifest path #{raw.inspect} escapes the plugin root" if cleaned.nil?

            cleaned
          end.uniq
        end

        # --- skills --------------------------------------------------------------

        def collect_skills
          locations = (["skills"] + manifest_paths(manifest["skills"])).uniq
          skills = locations.flat_map { |location| skills_at(location) }
          skills << root_skill if @files.key?("SKILL.md") && skills.none? { |skill| skill.path == "" }
          skills.each do |skill|
            skill.files.each { |rel, data| @tree["skills/#{skill.name}/#{rel}"] = data }
            @consumed.concat(skill.files.keys.map { |rel| skill.path.empty? ? rel : "#{skill.path}/#{rel}" })
          end
          skills
        end

        def skills_at(location)
          return [] if location.empty?
          return [skill_from_dir(location)] if @files.key?("#{location}/SKILL.md")

          dirs = @files.keys.filter_map do |path|
            next unless path.start_with?("#{location}/") && path.count("/") >= location.count("/") + 2

            path.delete_prefix("#{location}/").split("/").first
          end
          dirs.uniq.sort.filter_map { |dir| skill_from_dir("#{location}/#{dir}") if @files.key?("#{location}/#{dir}/SKILL.md") }
        end

        def skill_from_dir(dir)
          files = @files.select { |path, _| path.start_with?("#{dir}/") }.transform_keys { |path| path.delete_prefix("#{dir}/") }
          frontmatter = frontmatter!(files.fetch("SKILL.md"), "#{dir}/SKILL.md")
          skill_name = frontmatter["name"].to_s.strip
          directory = File.basename(dir)
          unless normalize_directory(skill_name) == normalize_directory(directory)
            raise InvalidPluginError, "#{dir}: frontmatter name #{skill_name.inspect} does not match its directory #{directory.inspect}"
          end

          build_skill(skill_name, frontmatter, files, kind: "skill", path: dir)
        end

        def root_skill
          files = @files.select { |path, _| path == "SKILL.md" || path.start_with?("scripts/", "references/", "assets/") }
          frontmatter = frontmatter!(files.fetch("SKILL.md"), "SKILL.md")
          build_skill(Manifest.presence(frontmatter["name"]) || name, frontmatter, files, kind: "skill", path: "")
        end

        def build_skill(skill_name, frontmatter, files, kind:, path:)
          validate_skill_name!(skill_name, path)
          description = frontmatter["description"].to_s.strip
          where = path.empty? ? "SKILL.md" : path
          raise InvalidPluginError, "#{where}: description is required" if description.empty?
          raise InvalidPluginError, "#{where}: description exceeds #{Validator::DESCRIPTION_MAX_LENGTH} characters" if description.length > Validator::DESCRIPTION_MAX_LENGTH

          Skill.new(name: skill_name, description: description, kind: kind, path: path, frontmatter: frontmatter, files: files)
        end

        def validate_skill_name!(skill_name, where)
          return if skill_name.match?(Validator::NAME_PATTERN) && skill_name.length <= Validator::NAME_MAX_LENGTH

          raise InvalidPluginError, "#{where}: skill name #{skill_name.inspect} must be lowercase letters, digits and single hyphens (1-#{Validator::NAME_MAX_LENGTH} chars)"
        end

        # Over skills and the commands that became skills: the cap and the names are one set.
        def check_skill_names!
          max = Marketplace.config.max_skills
          raise InvalidPluginError, "plugin has more than #{max} skills" if @skills.size > max

          duplicates = @skills.map(&:name).tally.select { |_, count| count > 1 }.keys
          raise InvalidPluginError, "duplicate skill names #{duplicates.inspect}" if duplicates.any?
        end

        # --- commands ------------------------------------------------------------

        def collect_commands
          markdown_files_at(manifest.key?("commands") ? manifest_paths(manifest["commands"]) : ["commands"]).filter_map do |path|
            command_from_file(path)
          end
        end

        def markdown_files_at(locations)
          locations.flat_map do |location|
            next [location] if @files.key?(location) && location.end_with?(".md")

            @files.keys.select { |path| path.start_with?("#{location}/") && path.end_with?(".md") }.sort
          end.uniq
        end

        # A command keeps its body; only `name` is pinned to the file name so
        # `/name` resolves. Without frontmatter or a description the loaders
        # cannot list it, so it is listed as unsupported and dropped.
        def command_from_file(path)
          command_name = path.delete_suffix(".md").split("/").drop(1).join("-").downcase.tr("_", "-")
          command_name = File.basename(path, ".md").downcase.tr("_", "-") if command_name.empty?
          text = text!(@files.fetch(path), path)
          frontmatter, body = split_frontmatter(text)
          if frontmatter.nil? || frontmatter["description"].to_s.strip.empty?
            @unsupported << {"name" => command_name, "path" => path, "reason" => frontmatter.nil? ? "missing_frontmatter" : "missing_description"}
            return nil
          end

          validate_skill_name!(command_name, path)
          pinned = frontmatter.merge("name" => command_name)
          rewritten = "---\n#{YAML.dump(pinned).delete_prefix("---\n")}---\n#{body}"
          @tree["skills/#{command_name}.md"] = rewritten
          @consumed << path
          build_skill(command_name, pinned, {"#{command_name}.md" => rewritten}, kind: "command", path: path)
        end

        # --- agents --------------------------------------------------------------

        def collect_agents
          markdown_files_at(manifest.key?("agents") ? manifest_paths(manifest["agents"]) : ["agents"]).map do |path|
            rel = "agents/#{path.split("/").drop(1).join("/")}"
            rel = "agents/#{File.basename(path)}" if rel == "agents/"
            @tree[rel] = @files.fetch(path)
            @consumed << path
            rel
          end
        end

        # --- references ----------------------------------------------------------

        # A skill that reads a plugin-level file (`../../references/x.md`,
        # `${CLAUDE_PLUGIN_ROOT}/defaults/`) gets a copy under `.plugin/` and
        # the text rewritten, so the skill tool (skill-root only, no `..`) can
        # serve it. Anything that resolves to nothing is left as text and listed.
        def relocate_references
          @skills.each do |skill|
            next if skill.command?

            skill.files.each_key do |rel|
              next unless rel.end_with?(".md")

              tree_path = "skills/#{skill.name}/#{rel}"
              text = text!(@tree.fetch(tree_path), tree_path)
              rewritten = text.gsub(ROOT_REFERENCE) { relocate(skill, rel, Regexp.last_match(1)) || Regexp.last_match(0) }
              rewritten = rewritten.gsub(RELATIVE_REFERENCE) { relocate_relative(skill, rel, Regexp.last_match(1)) || Regexp.last_match(0) }
              @tree[tree_path] = rewritten if rewritten != text
            end
          end
        end

        def relocate_relative(skill, rel, reference)
          return nil if skill.path.empty?

          source_dir = File.dirname(File.join(skill.path, rel))
          target = File.expand_path(reference, "/#{source_dir}").delete_prefix("/")
          return nil if target.empty? || target == skill.path || target.start_with?("#{skill.path}/") || target.start_with?("../")

          relocate(skill, rel, target)
        end

        # Copies +plugin_path+ (a file, or every file under it) into the skill's
        # support root; returns the rewritten reference relative to +rel+'s directory.
        def relocate(skill, rel, plugin_path)
          trimmed = plugin_path.sub(/[.,;:)\]'"`]+\z/, "")
          trailing = plugin_path[trimmed.length..]
          segments = trimmed.split("/")
          candidates = segments.length.downto(1).map { |n| segments.first(n).join("/") }
          matched = candidates.find { |candidate| @files.key?(candidate) || @files.keys.any? { |path| path.start_with?("#{candidate}/") } }
          if matched.nil?
            @unresolved_references << {"skill" => skill.name, "reference" => plugin_path}
            return nil
          end

          @files.select { |path, _| path == matched || path.start_with?("#{matched}/") }.each do |path, data|
            @tree["skills/#{skill.name}/#{SUPPORT_ROOT}/#{path}"] = data
            @consumed << path
          end
          rest = trimmed.delete_prefix(matched)
          from = File.dirname(rel)
          relative = Pathname.new("#{SUPPORT_ROOT}/#{matched}").relative_path_from(Pathname.new((from == ".") ? "" : from).cleanpath).to_s
          "#{relative}#{rest}#{trailing}"
        end

        # --- frontmatter ---------------------------------------------------------

        def frontmatter!(raw, path)
          frontmatter, _body = split_frontmatter(text!(raw, path))
          raise InvalidPluginError, "#{path}: missing YAML frontmatter" if frontmatter.nil?

          frontmatter
        end

        # [hash, body] when the text opens with a frontmatter block, else [nil, text].
        def split_frontmatter(text)
          return [nil, text] unless text.match?(Parser::FRONTMATTER_REGEX)

          data = Parser.parse_string(text)
          return [nil, text] unless data.is_a?(Hash)

          [data.transform_keys(&:to_s), Parser.extract_body(text)]
        rescue ParseError => e
          raise InvalidPluginError, "invalid YAML frontmatter (#{e.message[0, 60]})"
        end

        def normalize_directory(value)
          value.to_s.strip.downcase.tr("_", "-")
        end

        def blank?(value)
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end
      end
    end
  end
end
