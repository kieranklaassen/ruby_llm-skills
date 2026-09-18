# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestLocator < Minitest::Test
  include MarketplaceTestHelper

  Locator = RubyLLM::Skills::Marketplace::Locator

  def test_owner_repo
    source = Locator.parse("EveryInc/compound-writing")
    assert_equal "github", source.kind
    assert_equal "EveryInc/compound-writing", source.locator
    assert_nil source.ref
    refute source.pinned?
  end

  def test_owner_repo_with_ref_suffix_and_keyword
    assert_equal "v1.2.0", Locator.parse("acme/skills@v1.2.0").ref
    assert_equal "dev", Locator.parse("acme/skills@v1.2.0", ref: "dev").ref
    sha = "65a39f393687675ce170e6094757de20370365b9"
    assert Locator.parse("acme/skills", ref: sha).pinned?
  end

  def test_github_urls
    assert_equal "acme/skills", Locator.parse("https://github.com/acme/skills").locator
    assert_equal "acme/skills", Locator.parse("https://github.com/acme/skills.git").locator
    source = Locator.parse("https://github.com/acme/skills/tree/release/v2")
    assert_equal "release/v2", source.ref
  end

  def test_gitlab_urls_with_nested_groups
    source = Locator.parse("https://gitlab.com/group/sub/project/-/tree/dev")
    assert_equal "gitlab", source.kind
    assert_equal "group/sub/project", source.locator
    assert_equal "dev", source.ref
    assert_equal "group/project", Locator.parse("https://gitlab.com/group/project").locator
  end

  def test_hosted_json_urls
    source = Locator.parse("https://example.com/plugins/marketplace.json")
    assert_equal "url", source.kind
    assert_equal "https://example.com/plugins/marketplace.json", source.locator
  end

  def test_directories
    assert_equal "directory", Locator.parse("./marketplace").kind
    assert_equal "directory", Locator.parse(marketplace_fixture_path("basic")).kind
    assert_equal "directory", Locator.parse("/abs/path").kind
  end

  def test_to_s_and_hash_round_trip
    source = Locator.parse("acme/skills@v1")
    assert_equal "acme/skills@v1", source.to_s
    assert_equal source, Locator::Source.from_h(source.to_h)
    assert_equal({"kind" => "github", "locator" => "acme/skills"}, Locator.parse("acme/skills").to_h)
  end

  def test_rejections
    assert_raises(ArgumentError) { Locator.parse("") }
    assert_raises(ArgumentError) { Locator.parse("just-a-name") }
    assert_raises(ArgumentError) { Locator.parse("http://github.com/acme/skills") }
    assert_raises(ArgumentError) { Locator.parse("https://user:pw@github.com/acme/skills") }
    assert_raises(ArgumentError) { Locator.parse("https://github.com/acme") }
    assert_raises(ArgumentError) { Locator.parse("https://bitbucket.org/acme/skills") }
    assert_raises(ArgumentError) { Locator.parse("acme/skills", ref: "bad ref") }
    assert_raises(ArgumentError) { Locator.parse("https://example.com/m.json", ref: "main") }
    assert_raises(ArgumentError) { Locator.parse("a" * 501) }
  end
end
