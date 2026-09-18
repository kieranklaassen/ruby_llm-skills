# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"
require "support/vcr_configuration"

# The one recorded round trip against a real marketplace: typesafe-ai/skills
# at a pinned commit, so the cassette stays valid as the repository moves.
class RubyLLM::Skills::Marketplace::TestRegistryLive < Minitest::Test
  include MarketplaceTestHelper

  COMMIT = "65a39f393687675ce170e6094757de20370365b9"

  def setup
    super
    VCR.turn_on!
  end

  def test_add_and_install_typesafe_skills_at_a_pinned_commit
    VCR.use_cassette("marketplace_typesafe_skills") do
      record = registry.add("typesafe-ai/skills", ref: COMMIT)
      assert_equal "typesafe-ai", record.name
      assert_equal COMMIT, record.commit
      assert record.pinned?
      assert_equal ["typesafe"], registry.plugins("typesafe-ai").map(&:name)

      result = registry.install("typesafe-ai")
      assert result.success?, result.errors.inspect
      assert_equal ["typesafe-ai/typesafe"], result.installed
    end

    plugin = registry.installed.first
    assert_equal COMMIT, plugin.commit
    assert_equal "0.5.7", plugin.version
    assert_equal "manifest", plugin.version_kind
    assert_equal ["typesafe-ai"], plugin.skills
    assert File.file?(File.join(scratch_root, "typesafe-ai", "typesafe", "skills", "typesafe-ai", "SKILL.md"))

    skill = registry.loader.find("typesafe-ai")
    assert skill.valid?, skill.errors.inspect
    assert_includes skill.content.downcase, "typesafe"

    lock = lockfile_json["marketplaces"]["typesafe-ai"]
    assert_equal({"kind" => "github", "locator" => "typesafe-ai/skills", "ref" => COMMIT, "commit" => COMMIT}, lock.except("plugins"))
  end
end
