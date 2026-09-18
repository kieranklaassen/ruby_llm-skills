# frozen_string_literal: true

require "fileutils"
require "securerandom"

module RubyLLM
  module Skills
    module Marketplace
      # The public surface: marketplaces recorded in a lockfile, their plugins
      # installed under a root directory, and a loader over what is installed.
      #
      # @example
      #   marketplaces = RubyLLM::Skills.marketplaces           # vendor/skills + skills.lock.json
      #   marketplaces.add("EveryInc/compound-writing")          # follows the default branch
      #   marketplaces.add("typesafe-ai/skills", ref: "v0.5.7")  # pinned to a tag
      #   marketplaces.plugins("compound-writing").map(&:name)
      #   marketplaces.install("compound-writing")               # every supported plugin
      #   marketplaces.install("typesafe-ai", only: ["typesafe"])
      #   marketplaces.install                                   # reproduce the lockfile
      #   marketplaces.update                                    # move every unpinned ref forward
      #   marketplaces.remove("typesafe-ai")
      #   chat.with_skills(marketplaces)
      #
      class Registry
        SCRATCH_PREFIX = ".building-"

        # One recorded marketplace.
        Record = Data.define(:name, :source, :commit, :plugins) do
          def kind = source.kind

          def locator = source.locator

          def ref = source.ref

          def pinned? = source.pinned?

          def plugin_names = plugins.keys
        end

        # One installed plugin.
        InstalledPlugin = Data.define(:marketplace, :name, :version, :version_kind, :commit, :tree_sha256, :source, :skills, :path) do
          def skills_path
            File.join(path, "skills")
          end

          def to_s
            "#{marketplace}/#{name}"
          end
        end

        # What an install or update did, keyed by "marketplace/plugin".
        Result = Data.define(:installed, :updated, :unchanged, :skipped, :errors) do
          def self.empty
            new(installed: [], updated: [], unchanged: [], skipped: {}, errors: {})
          end

          def success? = errors.empty?

          def changed = installed + updated
        end

        attr_reader :root, :lockfile_path

        # @param root [String] where plugins are written (default: Marketplace.root)
        # @param lockfile [String] the lockfile path (default: Marketplace.lockfile)
        def initialize(root: Marketplace.root, lockfile: Marketplace.lockfile)
          @root = File.expand_path(root.to_s)
          @lockfile_path = File.expand_path(lockfile.to_s)
        end

        # Records a marketplace and caches its marketplace file; installs nothing.
        #
        # @param locator [String] `owner/repo`, `owner/repo@ref`, a repository URL, a hosted `.json` URL, or a directory
        # @param ref [String, nil] a branch, tag or commit sha to pin the marketplace to
        # @param as [String, nil] the name to record it under (default: the marketplace file's `name`)
        # @return [Record]
        # @raise [FetchError, InvalidManifestError, ArgumentError]
        def add(locator, ref: nil, as: nil)
          source = Locator.parse(locator, ref: ref)
          fetcher = Fetcher.for(source)
          head = fetcher.head
          files = fetcher.catalog_files(head)
          catalog = Manifest.discover(files)
          name = Manifest.presence(as) || catalog.name
          raise ArgumentError, "#{name.inspect} is not a valid marketplace name" unless name.match?(Manifest::NAME_PATTERN)

          existing = lockfile.marketplace(name)
          if existing && Locator::Source.from_h(existing) != source
            raise ArgumentError, "a marketplace named #{name.inspect} is already added from #{Locator::Source.from_h(existing)}; pass as: to add this one under another name"
          end

          cache_catalog!(name, files)
          lockfile.set_marketplace(name, source.to_h.merge("commit" => head.sha))
          lockfile.save
          reload!
          find(name)
        end

        # @return [Array<Record>] every recorded marketplace
        def list
          lockfile.names.map { |name| record(name) }
        end

        # @return [Record, nil]
        def find(name)
          lockfile.marketplace(name) && record(name)
        end

        # @return [Record]
        # @raise [NotFoundError]
        def fetch(name)
          find(name) || raise(NotFoundError, "Marketplace not found: #{name}")
        end

        # The plugins a marketplace lists, from the cached marketplace file.
        #
        # @return [Array<Manifest::Entry>]
        def plugins(name)
          catalog(fetch(name)).plugins
        end

        # Installs plugins. With a marketplace name, every supported plugin of
        # that marketplace (or +only+ the named ones) at the marketplace's
        # recorded commit. With no name, every plugin in the lockfile at its
        # recorded commit, so a fresh checkout reproduces the same trees.
        #
        # @return [Result]
        # @raise [NotFoundError] for an unknown marketplace or plugin name
        def install(name = nil, only: nil)
          result = Result.empty
          if name.nil?
            list.each { |record| install_plugins(record, record.plugin_names, result, reproduce: true) }
          else
            record = fetch(name)
            wanted = only ? Array(only).map(&:to_s) : supported_plugin_names(record)
            install_plugins(record, wanted, result, reproduce: false)
          end
          finish(result)
        end

        # Moves marketplaces forward: re-resolves each ref, re-reads the
        # marketplace file when the head moved, refetches installed plugins
        # whose source moved, and rewrites the lockfile. A marketplace pinned
        # to a commit never moves.
        #
        # @return [Result]
        def update(name = nil, only: nil)
          result = Result.empty
          records = name ? [fetch(name)] : list
          records.each do |record|
            record = refresh_head!(record)
            wanted = only ? Array(only).map(&:to_s) : record.plugin_names
            install_plugins(record, wanted, result, reproduce: false)
          end
          finish(result)
        end

        # Deletes a marketplace's directory and lockfile entry.
        def remove(name)
          record = fetch(name)
          FileUtils.rm_rf(marketplace_dir(record.name))
          lockfile.delete_marketplace(record.name)
          lockfile.save
          reload!
          record
        end

        # Deletes one plugin's directory and lockfile entry.
        def uninstall(name, plugin)
          record = fetch(name)
          installed = record.plugins[plugin.to_s] || raise(NotFoundError, "Plugin not installed: #{name}/#{plugin}")
          FileUtils.rm_rf(installed.path)
          lockfile.delete_plugin(record.name, plugin)
          lockfile.save
          reload!
          installed
        end

        # @return [Array<InstalledPlugin>] in lockfile order
        def installed
          list.flat_map { |record| record.plugins.values }
        end

        # A loader over every installed plugin's skills.
        #
        # @return [Loader]
        def loader
          loaders = installed.map { |plugin| FilesystemLoader.new(plugin.skills_path) }
          (loaders.length == 1) ? loaders.first : RubyLLM::Skills.compose(*loaders)
        end

        # Forget the cached lockfile so the next call re-reads it.
        def reload!
          @lockfile = nil
          self
        end

        def inspect
          "#<#{self.class.name} root=#{root.inspect} lockfile=#{lockfile_path.inspect}>"
        end

        private

        def lockfile
          @lockfile ||= Lockfile.load(lockfile_path)
        end

        def finish(result)
          lockfile.save
          reload!
          result
        end

        def record(name)
          data = lockfile.marketplace(name)
          source = Locator::Source.from_h(data)
          plugins = lockfile.plugins(name).sort.to_h do |plugin_name, plugin|
            [plugin_name, installed_plugin(name, plugin_name, plugin)]
          end
          Record.new(name: name, source: source, commit: data["commit"], plugins: plugins)
        end

        def installed_plugin(marketplace, plugin_name, data)
          InstalledPlugin.new(marketplace: marketplace, name: plugin_name, version: data["version"], version_kind: data["version_kind"],
            commit: data["commit"], tree_sha256: data["tree_sha256"], source: Manifest::PluginSource.from_h(data["source"] || {}),
            skills: Array(data["skills"]), path: plugin_dir(marketplace, plugin_name))
        end

        def marketplace_dir(name)
          File.join(root, safe_name(name))
        end

        def plugin_dir(marketplace, plugin)
          File.join(marketplace_dir(marketplace), safe_name(plugin))
        end

        # Names come from marketplace files and the lockfile; only a kebab-case
        # name may become a directory under the root.
        def safe_name(name)
          raise LockfileError, "unsafe name #{name.inspect}" unless name.to_s.match?(Manifest::NAME_PATTERN)

          name.to_s
        end

        def cache_catalog!(name, files)
          dir = marketplace_dir(name)
          Manifest::PATHS.each { |path| FileUtils.rm_f(File.join(dir, path)) }
          Tarball.write_directory(files, dir)
        end

        def catalog(record)
          dir = marketplace_dir(record.name)
          files = Manifest::PATHS.each_with_object({}) do |path, found|
            full = File.join(dir, path)
            found[path] = File.binread(full) if File.file?(full)
          end
          return Manifest.discover(files) unless files.empty?

          fetcher = Fetcher.for(record.source)
          head = recorded_head(record)
          files = fetcher.catalog_files(head)
          cache_catalog!(record.name, files)
          Manifest.discover(files)
        end

        def supported_plugin_names(record)
          catalog(record).plugins.select(&:supported?).map(&:name)
        end

        # Re-resolves the ref; on a move, re-reads and caches the marketplace file.
        def refresh_head!(record)
          fetcher = Fetcher.for(record.source)
          head = fetcher.head(previous_sha: record.commit)
          return record if head.unchanged? && catalog_cached?(record)

          cache_catalog!(record.name, fetcher.catalog_files(head))
          lockfile.set_marketplace(record.name, record.source.to_h.merge("commit" => head.sha))
          Record.new(name: record.name, source: record.source, commit: head.sha, plugins: record.plugins)
        end

        def catalog_cached?(record)
          Manifest::PATHS.any? { |path| File.file?(File.join(marketplace_dir(record.name), path)) }
        end

        # A Head standing at the recorded commit, so relative sources read the
        # marketplace tree exactly as it was recorded. A directory marketplace
        # has no history: its head is what the folder holds now.
        def recorded_head(record)
          fetcher = Fetcher.for(record.source)
          return fetcher.head if record.kind == "directory" || record.commit.nil?

          Fetcher::Head.new(sha: record.commit, etag: nil, unchanged: true)
        end

        def install_plugins(record, names, result, reproduce:)
          return if names.empty?

          catalog = self.catalog(record)
          unknown = names.reject { |plugin_name| catalog.plugin(plugin_name) || record.plugins[plugin_name] }
          raise NotFoundError, "Plugin not found in #{record.name}: #{unknown.join(", ")}" if unknown.any?

          fetcher = Fetcher.for(record.source)
          head = recorded_head(record)
          names.each do |plugin_name|
            key = "#{record.name}/#{plugin_name}"
            installed = record.plugins[plugin_name]
            entry = catalog.plugin(plugin_name)
            next result.errors[key] = "no longer listed by the marketplace" if entry.nil?
            next result.skipped[key] = "unsupported source (#{entry.source.reason})" unless entry.supported?
            next result.skipped[key] = "relative sources are not available from a hosted marketplace.json" if record.kind == "url" && entry.source.kind == "relative"

            install_plugin(record, fetcher, head, entry, installed, result, reproduce: reproduce)
          rescue FetchError, InvalidPluginError, InvalidManifestError => e
            result.errors[key] = e.message
          end
        end

        def install_plugin(record, fetcher, head, entry, installed, result, reproduce:)
          key = "#{record.name}/#{entry.name}"
          plugin_source = (reproduce && installed) ? pin_source(entry.source, installed) : entry.source
          sha = fetcher.source_sha(plugin_source, head: head)
          if installed && sha && sha == installed.commit && on_disk?(installed)
            return result.unchanged << key
          end

          fetched = fetcher.source_tree(plugin_source, head: head)
          if reproduce && installed && plugin_source.kind == "archive" && fetched.sha != installed.commit
            raise FetchError, "#{key}: archive digest #{fetched.sha[0, 12]} does not match the lockfile's #{installed.commit.to_s[0, 12]}"
          end

          bundle = Bundle.new(fetched.files, entry: entry)
          return result.skipped[key] = "no skills, commands or agents to install" if bundle.empty?
          if installed && installed.tree_sha256 == bundle.tree_sha256 && on_disk?(installed)
            lockfile.set_plugin(record.name, entry.name, plugin_data(entry, fetched, bundle))
            return result.unchanged << key
          end

          target = plugin_dir(record.name, entry.name)
          was_on_disk = File.directory?(target)
          write_tree!(target, bundle)
          lockfile.set_plugin(record.name, entry.name, plugin_data(entry, fetched, bundle))
          (was_on_disk ? result.updated : result.installed) << key
        end

        # The lockfile's commit, so a reproduce fetches what was recorded rather than the ref's current head.
        def pin_source(plugin_source, installed)
          return plugin_source unless %w[github gitlab].include?(plugin_source.kind) && installed.commit

          plugin_source.with(sha: installed.commit)
        end

        def on_disk?(installed)
          dir = installed.path
          File.directory?(dir) && Tarball.tree_sha256(Tarball.from_directory(dir)) == installed.tree_sha256
        end

        def plugin_data(entry, fetched, bundle)
          version, kind = if bundle.version
            [bundle.version, bundle.version_kind]
          else
            [fetched.sha, (entry.source.kind == "archive") ? "archive" : "commit"]
          end
          {"version" => version, "version_kind" => kind, "commit" => fetched.sha, "tree_sha256" => bundle.tree_sha256,
           "source" => entry.source.to_h, "skills" => bundle.skill_names}
        end

        # Written to a scratch directory beside the target and moved into
        # place with one rename, so a failure leaves no partial tree.
        def write_tree!(target, bundle)
          FileUtils.mkdir_p(File.dirname(target))
          scratch = File.join(File.dirname(target), "#{SCRATCH_PREFIX}#{File.basename(target)}-#{SecureRandom.hex(4)}")
          FileUtils.mkdir_p(scratch)
          Tarball.write_directory(bundle.tree, scratch)
          FileUtils.rm_rf(target)
          File.rename(scratch, target)
          target
        rescue
          FileUtils.rm_rf(scratch) if scratch && File.exist?(scratch)
          raise
        end
      end
    end
  end
end
