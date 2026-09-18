# frozen_string_literal: true

require "digest"

module RubyLLM
  module Skills
    module Marketplace
      # Where a marketplace's bytes come from: one adapter per source kind.
      # +head+ answers "did the upstream move?" cheaply (a commit sha or a
      # tree hash), +catalog_files+ fetches only the marketplace file(s),
      # +source_tree+ fetches one plugin's content (the marketplace's own tree
      # for relative sources, memoized so ten relative plugins cost one
      # download; another repository's archive for github / gitlab sources;
      # a .tar.gz for archive sources). Nothing here runs git.
      #
      module Fetcher
        Head = Data.define(:sha, :etag, :unchanged) do
          def unchanged? = unchanged
        end

        # +files+ is the plugin root as `{ path => bytes }`; +sha+ identifies the
        # content (a commit, a tree hash, an archive digest).
        Fetched = Data.define(:files, :sha, :upstream_url)

        # @param source [Locator::Source]
        # @return [Base]
        def self.for(source)
          case source.kind
          when "github" then Github.new(source)
          when "gitlab" then Gitlab.new(source)
          when "url" then Url.new(source)
          when "directory" then Directory.new(source)
          else raise FetchError, "unknown marketplace kind #{source.kind.inspect}"
          end
        end

        class Base
          # Directories that carry plugin content, so an archive holding only
          # one of them is the plugin root rather than a wrapping folder.
          PLUGIN_ROOTS = %w[skills commands agents].freeze

          attr_reader :source

          def initialize(source)
            @source = source
            @tarballs = {}
            @shas = {}
          end

          def head(previous_sha: nil, previous_etag: nil)
            raise NotImplementedError
          end

          # `{ path => bytes }` for the marketplace files that exist at +head+.
          def catalog_files(head)
            raise NotImplementedError
          end

          # The plugin content for one marketplace entry.
          #
          # @param plugin_source [Manifest::PluginSource]
          # @param head [Head]
          # @return [Fetched]
          def source_tree(plugin_source, head:)
            case plugin_source.kind
            when "relative" then relative_tree(plugin_source, head)
            when "github" then repo_tree(GithubRepo.new(plugin_source.repo), plugin_source)
            when "gitlab" then repo_tree(GitlabRepo.new(plugin_source.repo), plugin_source)
            when "archive" then archive_tree(plugin_source)
            else raise FetchError, "unsupported source (#{plugin_source.reason})"
            end
          end

          # The commit a source resolves to right now, without downloading it
          # (nil for an archive, whose identity is its digest).
          def source_sha(plugin_source, head:)
            case plugin_source.kind
            when "relative" then head.sha
            when "github" then repo_sha(GithubRepo.new(plugin_source.repo), plugin_source)
            when "gitlab" then repo_sha(GitlabRepo.new(plugin_source.repo), plugin_source)
            end
          end

          private

          def relative_tree(plugin_source, head)
            Fetched.new(files: read_tree(head.sha, plugin_source.path), sha: head.sha, upstream_url: tree_url(head.sha, plugin_source.path))
          end

          def repo_sha(repo, plugin_source)
            plugin_source.sha || @shas[[repo.class, repo.repo, plugin_source.ref]] ||= repo.commit(plugin_source.ref || repo.default_branch).first
          end

          def repo_tree(repo, plugin_source)
            sha = repo_sha(repo, plugin_source)
            Fetched.new(files: Tarball.read(tarball(repo, sha), subdir: plugin_source.path), sha: sha, upstream_url: repo.tree_url(sha, plugin_source.path))
          end

          # One download per repository commit however many plugins live in it.
          def tarball(repo, sha)
            @tarballs[[repo.class, repo.repo, sha]] ||= repo.tarball(sha)
          end

          def archive_tree(plugin_source)
            response = Http.get(plugin_source.url, public: true)
            raise FetchError, "archive returned HTTP #{response.status}" unless response.success?

            digest = Digest::SHA256.hexdigest(response.body)
            raise FetchError, "archive sha256 mismatch for #{plugin_source.url}" if plugin_source.sha256 && plugin_source.sha256 != digest

            files = Tarball.read(response.body, strip_root: false)
            Fetched.new(files: strip_single_root(files), sha: digest, upstream_url: plugin_source.url)
          end

          # An archive may carry the plugin at its top or one folder down.
          def strip_single_root(files)
            roots = files.keys.map { |path| path.split("/", 2) }
            return files if roots.any? { |parts| parts.size == 1 } || roots.map(&:first).uniq.size != 1
            return files if PLUGIN_ROOTS.include?(roots.first.first)

            files.transform_keys { |path| path.split("/", 2).last }
          end

          def subtree(files, subdir, where)
            prefix = Manifest.presence(subdir)
            return files if prefix.nil?

            subset = files.select { |path, _| path.start_with?("#{prefix}/") }.transform_keys { |path| path.delete_prefix("#{prefix}/") }
            raise FetchError, "#{where}/#{prefix} has no files" if subset.empty?

            subset
          end
        end

        # A repository over one of the repo clients (GitHub, GitLab).
        class Repository < Base
          def repo
            raise NotImplementedError
          end

          def head(previous_sha: nil, previous_etag: nil)
            ref = source.ref || repo.default_branch
            result = repo.commit(ref, etag: previous_etag)
            return Head.new(sha: previous_sha, etag: previous_etag, unchanged: true) if result == :not_modified

            sha, etag = result
            Head.new(sha: sha, etag: etag, unchanged: sha == previous_sha)
          end

          def catalog_files(head)
            Manifest::PATHS.each_with_object({}) do |path, files|
              body = repo.file(head.sha, path)
              files[path] = body if body
            end
          end

          private

          def read_tree(sha, subdir)
            Tarball.read(tarball(repo, sha), subdir: subdir)
          end

          def tree_url(sha, subdir)
            repo.tree_url(sha, subdir)
          end
        end

        class Github < Repository
          def repo
            @repo ||= GithubRepo.new(source.locator)
          end
        end

        class Gitlab < Repository
          def repo
            @repo ||= GitlabRepo.new(source.locator)
          end
        end

        # A bare `https://…/marketplace.json`: the file is the whole upstream,
        # so relative sources cannot be fetched (as in Claude Code); github,
        # gitlab and archive entries work.
        class Url < Base
          def head(previous_sha: nil, previous_etag: nil)
            response = fetch(etag: previous_etag)
            return Head.new(sha: previous_sha, etag: previous_etag, unchanged: true) if response.not_modified?

            @body = response.body
            sha = Digest::SHA256.hexdigest(response.body)
            Head.new(sha: sha, etag: response.etag, unchanged: sha == previous_sha)
          end

          def catalog_files(_head)
            {Manifest::PATHS.first => @body || fetch.body}
          end

          private

          def fetch(etag: nil)
            response = Http.get(source.locator, public: true, max_bytes: Manifest::MAX_BYTES, etag: etag)
            raise FetchError, "marketplace URL returned HTTP #{response.status}" unless response.success? || response.not_modified?

            response
          end

          def read_tree(_sha, _subdir)
            raise FetchError, "relative sources are not available from a hosted marketplace.json"
          end

          def tree_url(_sha, _subdir)
            source.locator
          end
        end

        # A local folder holding a marketplace file. The tree's sha256 is the
        # head, so an update is a local read that does nothing until the
        # folder changes.
        class Directory < Base
          def root
            dir = File.expand_path(source.locator)
            raise FetchError, "marketplace directory #{source.locator} does not exist" unless File.directory?(dir)

            dir
          end

          def head(previous_sha: nil, previous_etag: nil)
            @files = nil
            sha = Tarball.tree_sha256(files)
            Head.new(sha: sha, etag: nil, unchanged: sha == previous_sha)
          end

          def catalog_files(_head)
            files.slice(*Manifest::PATHS)
          end

          private

          def files
            @files ||= Tarball.from_directory(root)
          end

          def read_tree(_sha, subdir)
            subtree(files, subdir, source.locator)
          end

          # A local folder has no public tree to link to.
          def tree_url(_sha, _subdir)
            nil
          end
        end
      end
    end
  end
end
