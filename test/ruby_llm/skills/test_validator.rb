# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class RubyLLM::Skills::TestValidator < Minitest::Test
  def test_valid_skill_returns_no_errors
    skill = build_skill(name: "valid-skill", description: "A valid description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_empty errors
  end

  def test_valid_returns_true_for_valid_skill
    skill = build_skill(name: "valid-skill", description: "A valid description")
    assert RubyLLM::Skills::Validator.valid?(skill)
  end

  def test_valid_returns_false_for_invalid_skill
    skill = build_skill(name: nil, description: "A description")
    refute RubyLLM::Skills::Validator.valid?(skill)
  end

  # Name validation tests
  def test_missing_name_returns_error
    skill = build_skill(name: nil, description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_includes errors, "name is required"
  end

  def test_empty_name_returns_error
    skill = build_skill(name: "", description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_includes errors, "name is required"
  end

  def test_name_too_long_returns_error
    skill = build_skill(name: "a" * 65, description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("name exceeds maximum length") }
  end

  def test_name_with_uppercase_returns_error
    skill = build_skill(name: "Invalid-Name", description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("must be lowercase") }
  end

  def test_name_with_underscore_returns_error
    skill = build_skill(name: "invalid_name", description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("must be lowercase") }
  end

  def test_name_starting_with_hyphen_returns_error
    skill = build_skill(name: "-invalid", description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("must be lowercase") }
  end

  def test_name_ending_with_hyphen_returns_error
    skill = build_skill(name: "invalid-", description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("must be lowercase") }
  end

  def test_name_with_consecutive_hyphens_returns_error
    skill = build_skill(name: "invalid--name", description: "A description")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("must be lowercase") }
  end

  def test_valid_names_accepted
    valid_names = %w[skill my-skill skill123 my-123-skill a1-b2-c3]
    valid_names.each do |name|
      skill = build_skill(name: name, description: "A description", path: "/path/to/#{name}")
      errors = RubyLLM::Skills::Validator.validate(skill)
      assert_empty errors, "Expected '#{name}' to be valid but got: #{errors.inspect}"
    end
  end

  # Description validation tests
  def test_missing_description_returns_error
    skill = build_skill(name: "valid-skill", description: nil)
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_includes errors, "description is required"
  end

  def test_empty_description_returns_error
    skill = build_skill(name: "valid-skill", description: "")
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_includes errors, "description is required"
  end

  def test_description_too_long_returns_error
    skill = build_skill(name: "valid-skill", description: "a" * 1025)
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("description exceeds maximum length") }
  end

  # License validation tests
  def test_license_too_long_returns_error
    skill = build_skill(
      name: "valid-skill",
      description: "A description",
      license: "a" * 129
    )
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("license exceeds maximum length") }
  end

  def test_valid_license_accepted
    skill = build_skill(
      name: "valid-skill",
      description: "A description",
      license: "MIT"
    )
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_empty errors
  end

  # Compatibility validation tests
  def test_compatibility_too_long_returns_error
    skill = build_skill(
      name: "valid-skill",
      description: "A description",
      compatibility: "a" * 501
    )
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("compatibility exceeds maximum length") }
  end

  def test_valid_compatibility_accepted
    skill = build_skill(
      name: "valid-skill",
      description: "A description",
      compatibility: "RubyLLM 1.0+"
    )
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_empty errors
  end

  # Path-name match validation tests
  def test_path_name_mismatch_returns_error
    skill = build_skill(
      name: "skill-name",
      description: "A description",
      path: "/path/to/different-name"
    )
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert errors.any? { |e| e.include?("does not match directory name") }
  end

  def test_path_name_match_passes
    skill = build_skill(
      name: "my-skill",
      description: "A description",
      path: "/path/to/my-skill"
    )
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_empty errors
  end

  def test_virtual_skill_skips_path_validation
    skill = build_skill(
      name: "my-skill",
      description: "A description",
      path: "database:123"
    )
    errors = RubyLLM::Skills::Validator.validate(skill)
    assert_empty errors
  end

  # Integration with Skill#valid? and Skill#errors
  def test_skill_valid_method
    path = skill_fixture_path("valid-skill")
    metadata = RubyLLM::Skills::Parser.parse_file(File.join(path, "SKILL.md"))
    skill = RubyLLM::Skills::Skill.new(path: path, metadata: metadata)

    assert skill.valid?
    assert_empty skill.errors
  end

  def test_skill_errors_method_returns_validation_errors
    path = skill_fixture_path("missing-description")
    metadata = RubyLLM::Skills::Parser.parse_file(File.join(path, "SKILL.md"))
    skill = RubyLLM::Skills::Skill.new(path: path, metadata: metadata)

    refute skill.valid?
    assert_includes skill.errors, "description is required"
  end

  def test_numeric_name_and_description_are_read_as_strings
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "123"))
      File.write(File.join(dir, "123", "SKILL.md"), "---\nname: 123\ndescription: 2024\n---\nBody\n")
      loader = RubyLLM::Skills.from_directory(dir)
      skill = loader.list.first

      assert_equal "123", skill.name
      assert_equal "2024", skill.description
      assert_empty skill.errors
      assert_same skill, loader.find("123")
    end
  end

  def test_non_scalar_name_is_a_validation_error
    skill = build_skill(name: ["a", "b"], description: "Valid description")

    assert_includes skill.errors, "name must be lowercase letters, numbers, and single hyphens (no leading/trailing hyphens)"
  end

  private

  def build_skill(name:, description:, path: nil, license: nil, compatibility: nil)
    path ||= "/path/to/#{name || "skill"}"
    metadata = {"name" => name, "description" => description}
    metadata["license"] = license if license
    metadata["compatibility"] = compatibility if compatibility

    RubyLLM::Skills::Skill.new(path: path, metadata: metadata)
  end
end
