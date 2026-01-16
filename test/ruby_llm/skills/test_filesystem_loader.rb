# frozen_string_literal: true

require "test_helper"

class RubyLlm::Skills::TestFilesystemLoader < Minitest::Test
  def setup
    @skills_path = File.join(fixtures_path, "skills")
    @loader = RubyLlm::Skills::FilesystemLoader.new(@skills_path)
  end

  def test_initialize_with_path
    loader = RubyLlm::Skills::FilesystemLoader.new("/path/to/skills")
    assert_equal "/path/to/skills", loader.path
  end

  def test_initialize_accepts_pathname
    require "pathname"
    loader = RubyLlm::Skills::FilesystemLoader.new(Pathname.new("/path/to/skills"))
    assert_equal "/path/to/skills", loader.path
  end

  def test_list_returns_skills_array
    skills = @loader.list
    assert_instance_of Array, skills
    assert skills.all? { |s| s.is_a?(RubyLlm::Skills::Skill) }
  end

  def test_list_finds_all_skills_in_directory
    skills = @loader.list
    skill_names = skills.map(&:name)

    assert_includes skill_names, "valid-skill"
    assert_includes skill_names, "with-scripts"
    assert_includes skill_names, "with-all-resources"
  end

  def test_list_returns_empty_array_for_nonexistent_path
    loader = RubyLlm::Skills::FilesystemLoader.new("/nonexistent/path")
    assert_equal [], loader.list
  end

  def test_list_returns_empty_array_for_empty_directory
    Dir.mktmpdir do |tmpdir|
      loader = RubyLlm::Skills::FilesystemLoader.new(tmpdir)
      assert_equal [], loader.list
    end
  end

  def test_find_returns_skill_by_name
    skill = @loader.find("valid-skill")
    assert_instance_of RubyLlm::Skills::Skill, skill
    assert_equal "valid-skill", skill.name
  end

  def test_find_returns_nil_for_unknown_name
    skill = @loader.find("nonexistent-skill")
    assert_nil skill
  end

  def test_get_returns_skill_by_name
    skill = @loader.get("valid-skill")
    assert_instance_of RubyLlm::Skills::Skill, skill
    assert_equal "valid-skill", skill.name
  end

  def test_get_raises_not_found_error_for_unknown_name
    error = assert_raises(RubyLlm::Skills::NotFoundError) do
      @loader.get("nonexistent-skill")
    end
    assert_equal "Skill not found: nonexistent-skill", error.message
  end

  def test_exists_returns_true_for_existing_skill
    assert @loader.exists?("valid-skill")
  end

  def test_exists_returns_false_for_nonexistent_skill
    refute @loader.exists?("nonexistent-skill")
  end

  def test_reload_clears_cache
    # Load skills first
    initial_skills = @loader.list

    # Reload should clear cache
    result = @loader.reload!

    assert_same @loader, result
    refute_same initial_skills, @loader.list
  end

  def test_skills_are_cached
    first_list = @loader.list
    second_list = @loader.list

    assert_same first_list, second_list
  end

  def test_loaded_skill_has_correct_metadata
    skill = @loader.find("valid-skill")

    assert_equal "valid-skill", skill.name
    assert_equal "A valid test skill for unit testing", skill.description
    assert_equal "MIT", skill.license
  end

  def test_loaded_skill_can_access_content
    skill = @loader.find("valid-skill")
    content = skill.content

    assert_includes content, "# Valid Skill Instructions"
  end

  def test_loaded_skill_can_list_resources
    skill = @loader.find("with-all-resources")

    assert_equal 1, skill.scripts.length
    assert_equal 1, skill.references.length
    assert_equal 1, skill.assets.length
  end
end
