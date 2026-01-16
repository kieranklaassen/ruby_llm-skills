# frozen_string_literal: true

require "test_helper"

class RubyLlm::Skills::TestSkill < Minitest::Test
  def setup
    @valid_skill_path = skill_fixture_path("valid-skill")
    @metadata = {
      "name" => "valid-skill",
      "description" => "A valid test skill for unit testing",
      "license" => "MIT",
      "compatibility" => "RubyLLM 1.0+",
      "metadata" => {"author" => "test-org", "version" => "1.0"},
      "allowed-tools" => "Bash Read"
    }
  end

  def test_initialize_with_path_and_metadata
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)

    assert_equal @valid_skill_path, skill.path
    assert_equal @metadata, skill.metadata
  end

  def test_name_returns_from_metadata
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert_equal "valid-skill", skill.name
  end

  def test_description_returns_from_metadata
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert_equal "A valid test skill for unit testing", skill.description
  end

  def test_license_returns_from_metadata
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert_equal "MIT", skill.license
  end

  def test_compatibility_returns_from_metadata
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert_equal "RubyLLM 1.0+", skill.compatibility
  end

  def test_custom_metadata_returns_metadata_hash
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert_equal({"author" => "test-org", "version" => "1.0"}, skill.custom_metadata)
  end

  def test_custom_metadata_returns_empty_hash_when_missing
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: {"name" => "test"})
    assert_equal({}, skill.custom_metadata)
  end

  def test_allowed_tools_splits_string
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert_equal %w[Bash Read], skill.allowed_tools
  end

  def test_allowed_tools_returns_empty_array_when_missing
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: {"name" => "test"})
    assert_equal [], skill.allowed_tools
  end

  def test_content_loads_lazily_from_file
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    content = skill.content

    assert_includes content, "# Valid Skill Instructions"
    assert_includes content, "This is a valid skill used for testing"
  end

  def test_content_uses_precached_content_when_provided
    skill = RubyLlm::Skills::Skill.new(
      path: @valid_skill_path,
      metadata: @metadata,
      content: "Pre-loaded content"
    )
    assert_equal "Pre-loaded content", skill.content
  end

  def test_content_uses_metadata_content_key
    metadata = @metadata.merge("__content__" => "Content from metadata")
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: metadata)
    assert_equal "Content from metadata", skill.content
  end

  def test_scripts_lists_script_files
    path = skill_fixture_path("with-scripts")
    skill = RubyLlm::Skills::Skill.new(
      path: path,
      metadata: {"name" => "with-scripts", "description" => "test"}
    )

    scripts = skill.scripts
    assert_equal 2, scripts.length
    assert scripts.any? { |s| s.end_with?("helper.rb") }
    assert scripts.any? { |s| s.end_with?("setup.sh") }
  end

  def test_scripts_returns_empty_array_when_no_scripts_dir
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert_equal [], skill.scripts
  end

  def test_references_lists_reference_files
    path = skill_fixture_path("with-all-resources")
    skill = RubyLlm::Skills::Skill.new(
      path: path,
      metadata: {"name" => "with-all-resources", "description" => "test"}
    )

    references = skill.references
    assert_equal 1, references.length
    assert references.first.end_with?("guide.md")
  end

  def test_assets_lists_asset_files
    path = skill_fixture_path("with-all-resources")
    skill = RubyLlm::Skills::Skill.new(
      path: path,
      metadata: {"name" => "with-all-resources", "description" => "test"}
    )

    assets = skill.assets
    assert_equal 1, assets.length
    assert assets.first.end_with?("template.txt")
  end

  def test_filesystem_returns_true_for_filesystem_path
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    assert skill.filesystem?
  end

  def test_virtual_returns_false_for_filesystem_path
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    refute skill.virtual?
  end

  def test_virtual_returns_true_for_database_path
    skill = RubyLlm::Skills::Skill.new(path: "database:123", metadata: @metadata)
    assert skill.virtual?
  end

  def test_filesystem_returns_false_for_database_path
    skill = RubyLlm::Skills::Skill.new(path: "database:123", metadata: @metadata)
    refute skill.filesystem?
  end

  def test_skill_md_path_returns_path_for_filesystem
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    expected = File.join(@valid_skill_path, "SKILL.md")
    assert_equal expected, skill.skill_md_path
  end

  def test_skill_md_path_returns_nil_for_virtual
    skill = RubyLlm::Skills::Skill.new(path: "database:123", metadata: @metadata)
    assert_nil skill.skill_md_path
  end

  def test_content_returns_empty_for_virtual_skill
    skill = RubyLlm::Skills::Skill.new(path: "database:123", metadata: {"name" => "test"})
    assert_equal "", skill.content
  end

  def test_resources_return_empty_for_virtual_skill
    skill = RubyLlm::Skills::Skill.new(path: "database:123", metadata: {"name" => "test"})
    assert_equal [], skill.scripts
    assert_equal [], skill.references
    assert_equal [], skill.assets
  end

  def test_reload_clears_cached_values
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)

    # Load content to cache it
    skill.content
    skill.scripts

    # Reload should clear cache
    result = skill.reload!

    assert_same skill, result
  end

  def test_inspect_returns_readable_string
    skill = RubyLlm::Skills::Skill.new(path: @valid_skill_path, metadata: @metadata)
    inspect_str = skill.inspect

    assert_includes inspect_str, "RubyLlm::Skills::Skill"
    assert_includes inspect_str, "valid-skill"
    assert_includes inspect_str, @valid_skill_path
  end
end
