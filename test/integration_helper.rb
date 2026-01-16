# frozen_string_literal: true

require "dotenv/load"
require "ruby_llm/skills"
require "minitest/autorun"
require_relative "support/vcr_configuration"

# Configure RubyLLM for integration tests
RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "test-key")
end

# Use FixturesHelper from test_helper if not already defined
unless defined?(FixturesHelper)
  module FixturesHelper
    def fixtures_path
      File.expand_path("fixtures", __dir__)
    end

    def skill_fixture_path(name)
      File.join(fixtures_path, "skills", name)
    end
  end

  class Minitest::Test
    include FixturesHelper
  end
end
