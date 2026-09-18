# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestHttp < Minitest::Test
  include MarketplaceTestHelper

  Http = RubyLLM::Skills::Marketplace::Http
  FetchError = RubyLLM::Skills::Marketplace::FetchError

  def test_get_returns_status_body_and_lowercased_headers
    stub_request(:get, "https://api.github.com/x").to_return(status: 200, body: "ok", headers: {"ETag" => "\"abc\""})
    response = Http.get("https://api.github.com/x", hosts: ["api.github.com"])
    assert response.success?
    assert_equal "ok", response.body
    assert_equal "\"abc\"", response.etag
  end

  def test_get_sends_the_user_agent_and_etag
    stub = stub_request(:get, "https://api.github.com/x")
      .with(headers: {"User-Agent" => /ruby_llm-skills/, "If-None-Match" => "\"abc\""})
      .to_return(status: 304)
    response = Http.get("https://api.github.com/x", hosts: ["api.github.com"], etag: "\"abc\"")
    assert response.not_modified?
    assert_requested stub
  end

  def test_get_follows_redirects_to_allowlisted_hosts
    stub_request(:get, "https://api.github.com/a").to_return(status: 302, headers: {"Location" => "https://codeload.github.com/b"})
    stub_request(:get, "https://codeload.github.com/b").to_return(status: 200, body: "final")
    response = Http.get("https://api.github.com/a", hosts: %w[api.github.com codeload.github.com])
    assert_equal "final", response.body
  end

  def test_get_refuses_a_redirect_off_the_allowlist
    stub_request(:get, "https://api.github.com/a").to_return(status: 302, headers: {"Location" => "https://evil.example.com/b"})
    error = assert_raises(FetchError) { Http.get("https://api.github.com/a", hosts: ["api.github.com"]) }
    assert_includes error.message, "evil.example.com"
  end

  def test_get_stops_after_too_many_redirects
    (0..4).each do |n|
      stub_request(:get, "https://api.github.com/r#{n}").to_return(status: 302, headers: {"Location" => "https://api.github.com/r#{n + 1}"})
    end
    error = assert_raises(FetchError) { Http.get("https://api.github.com/r0", hosts: ["api.github.com"]) }
    assert_includes error.message, "too many redirects"
  end

  def test_get_refuses_http_and_credentials
    assert_raises(FetchError) { Http.get("http://api.github.com/x", hosts: ["api.github.com"]) }
    assert_raises(FetchError) { Http.get("https://user:pass@api.github.com/x", hosts: ["api.github.com"]) }
  end

  def test_get_refuses_a_host_outside_the_allowlist_unless_public
    stub_request(:get, "https://example.com/m.json").to_return(status: 200, body: "{}")
    assert_raises(FetchError) { Http.get("https://example.com/m.json", hosts: ["api.github.com"]) }
    assert_equal "{}", Http.get("https://example.com/m.json", public: true).body
  end

  def test_public_urls_pass_through_the_url_guard
    seen = []
    RubyLLM::Skills::Marketplace.config.url_guard = ->(uri) { seen << uri.host }
    stub_request(:get, "https://example.com/a").to_return(status: 302, headers: {"Location" => "https://cdn.example.com/b"})
    stub_request(:get, "https://cdn.example.com/b").to_return(status: 200, body: "x")
    Http.get("https://example.com/a", public: true)
    assert_equal %w[example.com cdn.example.com], seen
  end

  def test_a_url_guard_may_pin_the_connection_to_an_address
    RubyLLM::Skills::Marketplace.config.url_guard = ->(_uri) { "203.0.113.7" }
    pinned = nil
    fake = Net::HTTP.new("example.com", 443)
    fake.define_singleton_method(:ipaddr=) { |address| pinned = address }
    stub_request(:get, "https://example.com/a").to_return(status: 200, body: "x")
    Net::HTTP.stub(:new, fake) { Http.get("https://example.com/a", public: true) }
    assert_equal "203.0.113.7", pinned
  end

  def test_a_url_guard_that_raises_refuses_the_request
    RubyLLM::Skills::Marketplace.config.url_guard = ->(_uri) { raise FetchError, "private address" }
    error = assert_raises(FetchError) { Http.get("https://example.com/a", public: true) }
    assert_equal "private address", error.message
  end

  def test_get_abandons_bodies_past_the_cap
    stub_request(:get, "https://api.github.com/big").to_return(status: 200, body: "x" * 1000)
    error = assert_raises(FetchError) { Http.get("https://api.github.com/big", hosts: ["api.github.com"], max_bytes: 100) }
    assert_includes error.message, "exceeds 100 bytes"
  end

  def test_get_wraps_connection_failures
    stub_request(:get, "https://api.github.com/down").to_timeout
    error = assert_raises(FetchError) { Http.get("https://api.github.com/down", hosts: ["api.github.com"]) }
    assert_includes error.message, "api.github.com"
  end

  def test_json_parses_objects_and_rejects_garbage
    assert_equal({"a" => 1}, Http.json(Http::Response.new(status: 200, body: "{\"a\":1}", headers: {})))
    assert_equal({}, Http.json(Http::Response.new(status: 200, body: "[1]", headers: {})))
    assert_raises(FetchError) { Http.json(Http::Response.new(status: 200, body: "nope", headers: {})) }
  end
end
