# frozen_string_literal: true

module RubyLLM
  module Skills
    module Marketplace
      # Knobs for fetching marketplaces: caps, the GitHub token, and the
      # guard a marketplace author's URL must pass.
      #
      # @example
      #   RubyLLM::Skills::Marketplace.configure do |config|
      #     config.github_token = ENV["MARKETPLACE_GITHUB_TOKEN"]
      #     config.url_guard = ->(uri) { raise "nope" unless uri.host.end_with?(".example.com") }
      #   end
      #
      class Config
        MEBIBYTE = 1024 * 1024

        # Sent to GitHub hosts only; lifts the rate limit and reaches private repositories.
        attr_accessor :github_token
        # One plugin archive (compressed and expanded), one file inside it, files per plugin, skills per plugin.
        attr_accessor :max_archive_bytes, :max_file_bytes, :max_files, :max_skills
        attr_accessor :user_agent
        # Called with each URI hop of a URL a marketplace author supplied
        # (a hosted marketplace.json, an archive source). Raise to refuse.
        attr_accessor :url_guard

        def initialize
          @github_token = ENV.fetch("GITHUB_TOKEN", nil)
          @max_archive_bytes = 64 * MEBIBYTE
          @max_file_bytes = 16 * MEBIBYTE
          @max_files = 2000
          @max_skills = 200
          @user_agent = "ruby_llm-skills/#{RubyLLM::Skills::VERSION}"
          @url_guard = nil
        end
      end
    end
  end
end
