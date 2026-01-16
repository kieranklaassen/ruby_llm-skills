# frozen_string_literal: true

require "test_helper"

class RubyLLM::Skills::TestModule < Minitest::Test
  def setup
    @original_default_path = RubyLLM::Skills.default_path
    @skills_path = File.join(fixtures_path, "skills")
  end

  def teardown
    RubyLLM::Skills.default_path = @original_default_path
  end

  # Configuration tests
  def test_default_path_defaults_to_app_skills
    RubyLLM::Skills.default_path = "app/skills"
    assert_equal "app/skills", RubyLLM::Skills.default_path
  end

  def test_default_path_is_configurable
    RubyLLM::Skills.default_path = "custom/skills"
    assert_equal "custom/skills", RubyLLM::Skills.default_path
  end

  # from_directory tests
  def test_from_directory_returns_filesystem_loader
    loader = RubyLLM::Skills.from_directory(@skills_path)
    assert_instance_of RubyLLM::Skills::FilesystemLoader, loader
  end

  def test_from_directory_uses_default_path_when_no_argument
    RubyLLM::Skills.default_path = @skills_path
    loader = RubyLLM::Skills.from_directory
    assert_equal @skills_path, loader.path
  end

  def test_from_directory_can_list_skills
    loader = RubyLLM::Skills.from_directory(@skills_path)
    skills = loader.list
    assert skills.any? { |s| s.name == "valid-skill" }
  end

  # load tests
  def test_load_returns_skill
    skill_path = File.join(@skills_path, "valid-skill")
    skill = RubyLLM::Skills.load(skill_path)

    assert_instance_of RubyLLM::Skills::Skill, skill
    assert_equal "valid-skill", skill.name
  end

  def test_load_raises_on_missing_skill_md
    error = assert_raises(RubyLLM::Skills::LoadError) do
      RubyLLM::Skills.load("/nonexistent/path")
    end
    assert_match(/SKILL.md not found/, error.message)
  end

  def test_load_parses_skill_content
    skill_path = File.join(@skills_path, "valid-skill")
    skill = RubyLLM::Skills.load(skill_path)

    assert_equal "A valid test skill for unit testing", skill.description
    assert_includes skill.content, "# Valid Skill Instructions"
  end

  # compose tests
  def test_compose_returns_composite_loader
    loader1 = RubyLLM::Skills.from_directory(@skills_path)
    loader2 = RubyLLM::Skills.from_directory(@skills_path)

    composite = RubyLLM::Skills.compose(loader1, loader2)
    assert_instance_of RubyLLM::Skills::CompositeLoader, composite
  end

  def test_compose_combines_skills_from_multiple_loaders
    loader1 = RubyLLM::Skills.from_directory(@skills_path)
    loader2 = RubyLLM::Skills.from_directory(@skills_path)

    composite = RubyLLM::Skills.compose(loader1, loader2)
    skills = composite.list

    # Should have unique skills only (no duplicates)
    names = skills.map(&:name)
    assert_equal names.uniq, names
  end

  def test_compose_earlier_loader_takes_precedence
    Dir.mktmpdir do |tmpdir|
      # Create a skill in tmpdir with same name but different description
      skill_dir = File.join(tmpdir, "valid-skill")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), <<~SKILL)
        ---
        name: valid-skill
        description: Override description
        ---
        Override content
      SKILL

      loader1 = RubyLLM::Skills.from_directory(tmpdir)
      loader2 = RubyLLM::Skills.from_directory(@skills_path)

      composite = RubyLLM::Skills.compose(loader1, loader2)
      skill = composite.find("valid-skill")

      assert_equal "Override description", skill.description
    end
  end
end
