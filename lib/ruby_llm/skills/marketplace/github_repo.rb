# frozen_string_literal: true

require "erb"

module RubyLLM
  module Skills
    module Marketplace
      # One GitHub repository over the REST API and its archive hosts: the
      # default branch and a ref's head commit from api.github.com, single
      # files from raw.githubusercontent.com, the tree as a tarball from
      # codeload.github.com. The optional token lifts the rate limit and
      # reaches private repositories; it is sent to these hosts only.
      #
      class GithubRepo
        API = "api.github.com"
        RAW = "raw.githubusercontent.com"
        CODELOAD = "codeload.github.com"
        HOSTS = [API, RAW, CODELOAD].freeze
        SMALL = 16 * 1024 * 1024

        attr_reader :repo

        def initialize(repo, token: Marketplace.config.github_token)
          @repo = Manifest.normalize_repo(repo)
          raise FetchError, "invalid GitHub repository #{repo.inspect}" unless @repo.match?(Manifest::REPO_PATTERN)

          @token = Manifest.presence(token)
        end

        def default_branch
          Http.json(api("repos/#{repo}")).fetch("default_branch", "main").to_s
        end

        # The head commit of +ref+ (a branch, tag or sha): [sha, etag], or
        # :not_modified when the ETag still matches.
        def commit(ref, etag: nil)
          response = api("repos/#{repo}/commits/#{ERB::Util.url_encode(ref)}", etag: etag, allow_not_modified: true)
          return :not_modified if response.not_modified?

          sha = Http.json(response)["sha"].to_s
          raise FetchError, "#{repo}@#{ref}: no commit sha in the response" unless sha.match?(Manifest::SHA_PATTERN)

          [sha, response.etag]
        end

        # One file at +sha+, or nil when it does not exist.
        def file(sha, path)
          response = Http.get("https://#{RAW}/#{repo}/#{sha}/#{path}", hosts: HOSTS, headers: headers, max_bytes: SMALL)
          return nil if response.not_found?
          raise FetchError, "#{repo}: #{path} returned HTTP #{response.status}" unless response.success?

          response.body
        end

        def tarball(sha)
          response = Http.get("https://#{CODELOAD}/#{repo}/tar.gz/#{sha}", hosts: HOSTS, headers: headers)
          raise FetchError, "#{repo}: archive returned HTTP #{response.status}" unless response.success?

          response.body
        end

        # `{ "tag" =>, "url" =>, "name" =>, "published_at" => }` for a tag that has a GitHub release, else nil.
        def release(tag)
          response = api("repos/#{repo}/releases/tags/#{ERB::Util.url_encode(tag)}", allow_not_found: true)
          return nil if response.not_found?

          data = Http.json(response)
          {"tag" => tag, "url" => data["html_url"].to_s, "name" => data["name"].to_s, "published_at" => data["published_at"].to_s}
        end

        def tree_url(sha, subdir = nil)
          ["https://github.com/#{repo}/tree/#{sha}", Manifest.presence(subdir)].compact.join("/")
        end

        private

        def api(path, etag: nil, allow_not_modified: false, allow_not_found: false)
          response = Http.get("https://#{API}/#{path}", hosts: HOSTS, headers: headers.merge("Accept" => "application/vnd.github+json"),
            max_bytes: SMALL, etag: etag)
          return response if response.success? || (allow_not_modified && response.not_modified?) || (allow_not_found && response.not_found?)
          if [403, 429].include?(response.status) && response.headers["x-ratelimit-remaining"].to_s == "0"
            raise FetchError, "GitHub rate limit reached for #{repo}"
          end

          raise FetchError, "#{repo}: GitHub API returned HTTP #{response.status} for #{path.split("/").last}"
        end

        def headers
          @token ? {"Authorization" => "Bearer #{@token}"} : {}
        end
      end
    end
  end
end
