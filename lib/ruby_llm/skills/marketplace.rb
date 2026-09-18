# frozen_string_literal: true

require_relative "marketplace/config"
require_relative "marketplace/http"
require_relative "marketplace/tarball"
require_relative "marketplace/manifest"
require_relative "marketplace/locator"
require_relative "marketplace/github_repo"
require_relative "marketplace/gitlab_repo"
require_relative "marketplace/fetcher"
require_relative "marketplace/bundle"
require_relative "marketplace/lockfile"
require_relative "marketplace/registry"

module RubyLLM
  module Skills
    # Plugin marketplaces as a skill source.
    #
    # A marketplace is a Claude Code, Codex, or Cursor plugin marketplace
    # (a GitHub repository, GitLab project, hosted marketplace.json, or a
    # local directory). Its plugins are fetched over HTTPS, normalized into
    # the skills/ layout the loaders read, written under a vendor directory,
    # and recorded in a lockfile with their resolved commit and version.
    #
    # @example
    #   marketplaces = RubyLLM::Skills.marketplaces
    #   marketplaces.add("EveryInc/compound-writing")
    #   marketplaces.install("compound-writing")
    #   chat.with_skills(marketplaces)
    #
    module Marketplace
      # Base error for the marketplace layer.
      class Error < Skills::Error; end

      # Raised when an upstream cannot be reached or refuses the request.
      class FetchError < Error; end

      # Raised when a marketplace file is malformed.
      class InvalidManifestError < Error; end

      # Raised when a plugin's tree breaks the Agent Skills rules or the caps.
      class InvalidPluginError < Error; end

      # Raised when the lockfile cannot be read.
      class LockfileError < Error; end

      DEFAULT_ROOT = "vendor/skills"
      DEFAULT_LOCKFILE = "skills.lock.json"

      class << self
        attr_writer :root, :lockfile

        # Where installed plugins live (default: vendor/skills).
        def root
          @root || DEFAULT_ROOT
        end

        # Where the lockfile lives (default: skills.lock.json).
        def lockfile
          @lockfile || DEFAULT_LOCKFILE
        end

        def config
          @config ||= Config.new
        end

        # @yield [Config] the configuration to change
        def configure
          yield config
          config
        end

        def reset_config!
          @config = Config.new
        end
      end
    end
  end
end
