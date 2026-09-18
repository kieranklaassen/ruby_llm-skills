# frozen_string_literal: true

require "erb"

module RubyLLM
  module Skills
    module Marketplace
      # One gitlab.com project over API v4: a ref's head commit, single raw
      # files and the repository archive. Public projects only.
      #
      class GitlabRepo
        HOST = "gitlab.com"
        HOSTS = [HOST].freeze
        SMALL = 16 * 1024 * 1024

        attr_reader :repo

        def initialize(project)
          @repo = Manifest.normalize_repo(project)
          raise FetchError, "invalid GitLab project #{project.inspect}" unless @repo.match?(Manifest::PROJECT_PATTERN)
        end

        def default_branch
          Http.json(api("")).fetch("default_branch", "main").to_s
        end

        def commit(ref, etag: nil)
          response = api("/repository/commits/#{ERB::Util.url_encode(ref)}", etag: etag, allow_not_modified: true)
          return :not_modified if response.not_modified?

          sha = Http.json(response)["id"].to_s
          raise FetchError, "#{repo}@#{ref}: no commit id in the response" unless sha.match?(Manifest::SHA_PATTERN)

          [sha, response.etag]
        end

        def file(sha, path)
          response = Http.get("#{base}/repository/files/#{ERB::Util.url_encode(path)}/raw?ref=#{ERB::Util.url_encode(sha)}", hosts: HOSTS, max_bytes: SMALL)
          return nil if response.not_found?
          raise FetchError, "#{repo}: #{path} returned HTTP #{response.status}" unless response.success?

          response.body
        end

        def tarball(sha)
          response = Http.get("#{base}/repository/archive.tar.gz?sha=#{ERB::Util.url_encode(sha)}", hosts: HOSTS)
          raise FetchError, "#{repo}: archive returned HTTP #{response.status}" unless response.success?

          response.body
        end

        def tree_url(sha, subdir = nil)
          ["https://#{HOST}/#{repo}/-/tree/#{sha}", Manifest.presence(subdir)].compact.join("/")
        end

        private

        def base
          "https://#{HOST}/api/v4/projects/#{ERB::Util.url_encode(repo)}"
        end

        def api(path, etag: nil, allow_not_modified: false)
          response = Http.get("#{base}#{path}", hosts: HOSTS, max_bytes: SMALL, etag: etag)
          return response if response.success? || (allow_not_modified && response.not_modified?)
          raise FetchError, "GitLab rate limit reached for #{repo}" if response.status == 429

          raise FetchError, "#{repo}: GitLab API returned HTTP #{response.status}"
        end
      end
    end
  end
end
