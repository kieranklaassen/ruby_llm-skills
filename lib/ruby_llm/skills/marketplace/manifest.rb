# frozen_string_literal: true

require "json"
require "uri"
require "pathname"

module RubyLLM
  module Skills
    module Marketplace
      # The marketplace file. Claude Code's `.claude-plugin/marketplace.json`
      # is the native shape; Codex's `.agents/plugins/marketplace.json`
      # (`source: {source: "local", path}`, `interface.displayName`) and
      # Cursor's `.cursor-plugin/marketplace.json` (path-string / `{path}`
      # sources) share `name` / `owner` / `plugins[]{name, source}`.
      #
      # Every `source` variant becomes a PluginSource: `relative` (inside the
      # marketplace repository), `github` / `gitlab` (also from `url` and
      # `git-subdir` on those hosts), `archive` (a .tar.gz), or `unsupported`
      # with the reason people see (`npm`, `command`, zip, other hosts).
      #
      module Manifest
        PATHS = %w[.claude-plugin/marketplace.json .agents/plugins/marketplace.json .cursor-plugin/marketplace.json].freeze
        SHAPES = {
          ".claude-plugin/marketplace.json" => "claude",
          ".agents/plugins/marketplace.json" => "codex",
          ".cursor-plugin/marketplace.json" => "cursor"
        }.freeze
        NAME_PATTERN = /\A[a-z0-9]+(?:[-._][a-z0-9]+)*\z/i
        REPO_PATTERN = %r{\A[\w.-]+/[\w.-]+\z}
        PROJECT_PATTERN = %r{\A[\w.-]+(?:/[\w.-]+)+\z}
        SHA_PATTERN = /\A[0-9a-f]{40}\z/
        # plugin.json fields a marketplace entry may carry (strict: false makes the entry the plugin).
        OVERRIDE_FIELDS = %w[skills commands agents hooks mcpServers lspServers outputStyles].freeze
        MAX_BYTES = 10 * 1024 * 1024

        # The parsed marketplace file.
        Catalog = Data.define(:name, :display_name, :owner, :description, :version, :plugin_root, :plugins, :shape, :path, :raw) do
          def plugin(name)
            plugins.find { |entry| entry.name == name.to_s }
          end

          def to_h
            {"name" => name, "display_name" => display_name, "owner" => owner, "description" => description,
             "version" => version, "plugin_root" => plugin_root, "shape" => shape, "path" => path}
          end
        end

        # One `plugins[]` entry.
        Entry = Data.define(:name, :display_name, :description, :version, :category, :tags, :strict, :source, :overrides, :raw) do
          def strict? = strict

          def supported? = source.supported?

          def to_h
            {"name" => name, "displayName" => display_name, "description" => description, "version" => version,
             "category" => category, "tags" => tags, "strict" => strict, "source" => source.to_h}.compact
          end
        end

        # Where an entry's content comes from.
        PluginSource = Data.define(:kind, :path, :repo, :ref, :sha, :url, :sha256, :reason) do
          def supported? = kind != "unsupported"

          def to_h
            {"kind" => kind, "path" => path, "repo" => repo, "ref" => ref, "sha" => sha, "url" => url, "sha256" => sha256, "reason" => reason}.compact
          end

          def self.from_h(hash)
            hash = hash.to_h.transform_keys(&:to_s)
            new(kind: hash["kind"], path: hash["path"], repo: hash["repo"], ref: hash["ref"], sha: hash["sha"],
              url: hash["url"], sha256: hash["sha256"], reason: hash["reason"])
          end

          def self.unsupported(reason, raw = nil)
            url = raw.is_a?(Hash) ? Manifest.presence(raw["url"]) : nil
            new(kind: "unsupported", path: nil, repo: nil, ref: nil, sha: nil, url: url, sha256: nil, reason: reason)
          end
        end

        class << self
          # The marketplace file among +files+ (`{ path => bytes }`), in discovery order.
          def discover(files)
            path = PATHS.find { |candidate| files.key?(candidate) }
            raise InvalidManifestError, "no marketplace file (looked for #{PATHS.join(", ")})" if path.nil?

            parse(files.fetch(path), shape: SHAPES.fetch(path), path: path)
          end

          def parse(json, shape: "claude", path: PATHS.first)
            raise InvalidManifestError, "marketplace file exceeds #{MAX_BYTES} bytes" if json.is_a?(String) && json.bytesize > MAX_BYTES

            data = json.is_a?(Hash) ? json : JSON.parse(json.to_s.dup.force_encoding(Encoding::UTF_8))
            raise InvalidManifestError, "marketplace file is not a JSON object" unless data.is_a?(Hash)

            name = data["name"].to_s.strip
            raise InvalidManifestError, "marketplace name is required" if name.empty?
            raise InvalidManifestError, "marketplace name #{name.inspect} is not kebab-case" unless name.match?(NAME_PATTERN)
            raise InvalidManifestError, "marketplace has no plugins[]" unless data["plugins"].is_a?(Array)

            metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
            plugin_root = normalize_relative(metadata["pluginRoot"].to_s, allow_blank: true)
            plugins = data["plugins"].each_with_index.map { |entry, index| entry(entry, index, plugin_root: plugin_root) }
            duplicates = plugins.map(&:name).tally.select { |_, count| count > 1 }.keys
            raise InvalidManifestError, "duplicate plugin names #{duplicates.inspect}" if duplicates.any?

            display_name = presence(data.dig("interface", "displayName")) || presence(data["displayName"]) || name
            Catalog.new(name: name, display_name: display_name, owner: data["owner"].is_a?(Hash) ? data["owner"] : {},
              description: presence(data["description"] || metadata["description"]),
              version: presence(data["version"] || metadata["version"]),
              plugin_root: plugin_root, plugins: plugins, shape: shape, path: path, raw: data)
          rescue JSON::ParserError => e
            raise InvalidManifestError, "marketplace file is not valid JSON (#{e.message[0, 80]})"
          end

          def entry(raw, index, plugin_root: nil)
            raise InvalidManifestError, "plugins[#{index}] is not an object" unless raw.is_a?(Hash)

            name = raw["name"].to_s.strip
            raise InvalidManifestError, "plugins[#{index}] has no name" if name.empty?
            raise InvalidManifestError, "plugin name #{name.inspect} is not kebab-case" unless name.match?(NAME_PATTERN)

            Entry.new(name: name, display_name: presence(raw["displayName"]), description: presence(raw["description"]),
              version: presence(raw["version"]), category: presence(raw["category"]), tags: Array(raw["tags"]).map(&:to_s),
              strict: raw["strict"] != false, source: source(raw["source"], plugin_root: plugin_root),
              overrides: raw.slice(*OVERRIDE_FIELDS), raw: raw)
          end

          def source(raw, plugin_root: nil)
            case raw
            when String then relative(raw, plugin_root: plugin_root)
            when Hash then hash_source(raw, plugin_root: plugin_root)
            else PluginSource.unsupported("source_missing")
            end
          end

          def relative(path, plugin_root: nil)
            cleaned = normalize_relative(path, allow_blank: true)
            return PluginSource.unsupported("unsafe_path") if cleaned.nil?

            if presence(plugin_root) && !path.to_s.start_with?("./", ".")
              cleaned = [plugin_root, cleaned].reject { |part| part.to_s.empty? }.join("/")
            end
            PluginSource.new(kind: "relative", path: cleaned, repo: nil, ref: nil, sha: nil, url: nil, sha256: nil, reason: nil)
          end

          def github(repo, ref: nil, sha: nil, subdir: nil, raw: nil)
            repo_source("github", normalize_repo(repo), REPO_PATTERN, ref: ref, sha: sha, subdir: subdir, raw: raw)
          end

          def gitlab(project, ref: nil, sha: nil, subdir: nil, raw: nil)
            repo_source("gitlab", normalize_repo(project), PROJECT_PATTERN, ref: ref, sha: sha, subdir: subdir, raw: raw)
          end

          # `https://github.com/o/r[.git]`, `git@github.com:o/r.git`, `owner/repo`
          # and their gitlab.com twins; any other host is unsupported.
          def git_url(url, ref: nil, sha: nil, subdir: nil, raw: nil)
            text = url.to_s.strip
            return github(text, ref: ref, sha: sha, subdir: subdir, raw: raw) if text.match?(REPO_PATTERN) && !text.include?(":")

            host, path = split_git_url(text)
            case host
            when "github.com" then github(path, ref: ref, sha: sha, subdir: subdir, raw: raw)
            when "gitlab.com" then gitlab(path, ref: ref, sha: sha, subdir: subdir, raw: raw)
            else PluginSource.unsupported(host ? "unsupported_host" : "invalid_url", raw)
            end
          end

          def archive(url, sha256: nil, raw: nil)
            reason = archive_problem(url, sha256)
            return PluginSource.unsupported(reason, raw) if reason

            PluginSource.new(kind: "archive", path: "", repo: nil, ref: nil, sha: nil, url: URI.parse(url.to_s.strip).to_s,
              sha256: presence(sha256)&.downcase, reason: nil)
          end

          # A relative path inside the marketplace repo: "./x", "x", "./" and "."
          # are accepted; anything escaping the root is nil.
          def normalize_relative(path, allow_blank:)
            cleaned = clean_relative(path.to_s.strip)
            return cleaned unless cleaned == "."

            allow_blank ? "" : nil
          end

          # `owner/repo`, with a leading slash, trailing slash or `.git` removed.
          def normalize_repo(value)
            value.to_s.strip.delete_prefix("/").delete_suffix("/").delete_suffix(".git")
          end

          def presence(value)
            text = value.to_s.strip
            text.empty? ? nil : text
          end

          private

          def hash_source(raw, plugin_root:)
            kind = raw["source"].to_s
            case kind
            when "" then raw.key?("path") ? relative(raw["path"].to_s, plugin_root: plugin_root) : PluginSource.unsupported("source_missing", raw)
            when "local" then relative(raw["path"].to_s, plugin_root: plugin_root)
            when "github" then github(raw["repo"].to_s, ref: raw["ref"], sha: raw["sha"], raw: raw)
            when "url" then git_url(raw["url"].to_s, ref: raw["ref"], sha: raw["sha"], raw: raw)
            when "git-subdir" then git_url(raw["url"].to_s, ref: raw["ref"], sha: raw["sha"], subdir: raw["path"].to_s, raw: raw)
            when "archive" then archive(raw["url"].to_s, sha256: raw["sha256"], raw: raw)
            else PluginSource.unsupported("#{presence(kind) || "unknown"}_source", raw)
            end
          end

          def repo_source(kind, repo, pattern, ref:, sha:, subdir:, raw:)
            return PluginSource.unsupported("invalid_repo", raw) unless repo.match?(pattern)

            pin = presence(sha)
            return PluginSource.unsupported("invalid_sha", raw) if pin && !pin.match?(SHA_PATTERN)

            path = presence(subdir) ? normalize_relative(subdir, allow_blank: false) : ""
            return PluginSource.unsupported("unsafe_path", raw) if path.nil?

            PluginSource.new(kind: kind, path: path, repo: repo, ref: presence(ref), sha: pin, url: nil, sha256: nil, reason: nil)
          end

          def split_git_url(text)
            if (ssh = text.match(/\Agit@([\w.-]+):(.+)\z/))
              return [ssh[1].downcase, ssh[2]]
            end

            uri = URI.parse(text)
            return [nil, nil] unless uri.is_a?(URI::HTTPS) && presence(uri.host)

            [uri.host.downcase, uri.path.to_s]
          rescue URI::InvalidURIError
            [nil, nil]
          end

          def archive_problem(url, sha256)
            uri = URI.parse(url.to_s.strip)
            return "invalid_url" unless uri.is_a?(URI::HTTPS) && presence(uri.host)
            return "zip_archive" unless uri.path.to_s.match?(/\.(tar\.gz|tgz)\z/i)

            "invalid_sha256" if presence(sha256) && !sha256.to_s.match?(/\A[0-9a-f]{64}\z/i)
          rescue URI::InvalidURIError
            "invalid_url"
          end

          # nil when the path is absolute, escapes the root or carries unsafe bytes.
          def clean_relative(text)
            return nil if text.match?(%r{\A/|\\|\0})

            cleaned = text.empty? ? "." : Pathname.new(text).cleanpath.to_s
            cleaned unless cleaned == ".." || cleaned.start_with?("../")
          end
        end
      end
    end
  end
end
