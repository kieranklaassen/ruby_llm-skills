# frozen_string_literal: true

require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = File.join(__dir__, "..", "fixtures", "vcr_cassettes")
  config.hook_into :webmock
  config.allow_http_connections_when_no_cassette = false

  # Record mode: :once for first run, :none in CI
  config.default_cassette_options = {
    record: ENV["CI"] ? :none : :once,
    match_requests_on: [:method, :uri, :body]
  }

  # Filter sensitive API keys
  %w[
    ANTHROPIC_API_KEY
    OPENAI_API_KEY
  ].each do |key|
    config.filter_sensitive_data("<#{key}>") { ENV.fetch(key, nil) }
  end

  # Filter authorization headers
  config.before_record do |interaction|
    interaction.request.headers.delete("Authorization")
    interaction.request.headers.delete("X-Api-Key")
    interaction.response.headers.delete("Set-Cookie")
  end
end
