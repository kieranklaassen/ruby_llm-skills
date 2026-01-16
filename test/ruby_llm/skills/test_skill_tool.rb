# frozen_string_literal: true

require "test_helper"

class RubyLlm::Skills::TestSkillTool < Minitest::Test
  def setup
    @skills_path = File.join(fixtures_path, "skills")
    @loader = RubyLlm::Skills::FilesystemLoader.new(@skills_path)
    @tool = RubyLlm::Skills::SkillTool.new(@loader)
  end

  def test_initialize_with_loader
    tool = RubyLlm::Skills::SkillTool.new(@loader)
    assert_equal @loader, tool.loader
  end

  def test_name_returns_skill
    assert_equal "skill", @tool.name
  end

  def test_description_includes_available_skills_xml
    description = @tool.description

    assert_includes description, "<available_skills>"
    assert_includes description, "</available_skills>"
    assert_includes description, "<skill>"
    assert_includes description, "<name>valid-skill</name>"
    assert_includes description, "<description>A valid test skill for unit testing</description>"
  end

  def test_description_includes_all_skills
    description = @tool.description

    assert_includes description, "valid-skill"
    assert_includes description, "with-scripts"
    assert_includes description, "with-all-resources"
  end

  def test_description_escapes_xml_special_chars
    # Create a mock loader with special characters
    mock_skill = RubyLlm::Skills::Skill.new(
      path: "database:test",
      metadata: {
        "name" => "test-skill",
        "description" => "Test <with> special & \"chars'"
      }
    )
    mock_loader = MockLoader.new([mock_skill])
    tool = RubyLlm::Skills::SkillTool.new(mock_loader)

    description = tool.description
    assert_includes description, "&lt;with&gt;"
    assert_includes description, "&amp;"
    assert_includes description, "&quot;"
    assert_includes description, "&apos;"
  end

  def test_parameters_returns_json_schema
    params = @tool.parameters

    assert_equal "object", params[:type]
    assert params[:properties].key?(:skill_name)
    assert_equal "string", params[:properties][:skill_name][:type]
    assert_includes params[:required], "skill_name"
  end

  def test_call_returns_skill_content
    result = @tool.call(skill_name: "valid-skill")

    assert_includes result, "# Skill: valid-skill"
    assert_includes result, "# Valid Skill Instructions"
    assert_includes result, "This is a valid skill used for testing"
  end

  def test_call_returns_error_for_unknown_skill
    result = @tool.call(skill_name: "nonexistent-skill")

    assert_includes result, "Skill 'nonexistent-skill' not found"
    assert_includes result, "Available skills:"
  end

  def test_execute_is_alias_for_call
    result = @tool.execute(skill_name: "valid-skill")

    assert_includes result, "# Skill: valid-skill"
  end

  def test_call_includes_scripts_section_when_present
    result = @tool.call(skill_name: "with-scripts")

    assert_includes result, "## Available Scripts"
    assert_includes result, "helper.rb"
    assert_includes result, "setup.sh"
  end

  def test_call_includes_references_section_when_present
    result = @tool.call(skill_name: "with-all-resources")

    assert_includes result, "## Available References"
    assert_includes result, "guide.md"
  end

  def test_call_includes_assets_section_when_present
    result = @tool.call(skill_name: "with-all-resources")

    assert_includes result, "## Available Assets"
    assert_includes result, "template.txt"
  end

  def test_to_tool_definition_returns_complete_definition
    definition = @tool.to_tool_definition

    assert_equal "skill", definition[:name]
    assert definition[:description].is_a?(String)
    assert definition[:parameters].is_a?(Hash)
  end

  def test_description_handles_empty_loader
    empty_loader = RubyLlm::Skills::FilesystemLoader.new("/nonexistent/path")
    tool = RubyLlm::Skills::SkillTool.new(empty_loader)

    description = tool.description
    assert_includes description, "<available_skills>"
    assert_includes description, "No skills available"
  end

  def test_works_with_database_loader
    require "ruby_llm/skills/database_loader"

    records = [
      MockDatabaseRecord.new(
        id: 1,
        name: "db-skill",
        description: "A database skill",
        content: "# Database Skill Content"
      )
    ]
    loader = RubyLlm::Skills::DatabaseLoader.new(records)
    tool = RubyLlm::Skills::SkillTool.new(loader)

    description = tool.description
    assert_includes description, "<name>db-skill</name>"

    result = tool.call(skill_name: "db-skill")
    assert_includes result, "# Database Skill Content"
  end

  def test_works_with_composite_loader
    loader1 = RubyLlm::Skills::FilesystemLoader.new(@skills_path)
    composite = RubyLlm::Skills::CompositeLoader.new([loader1])
    tool = RubyLlm::Skills::SkillTool.new(composite)

    description = tool.description
    assert_includes description, "valid-skill"

    result = tool.call(skill_name: "valid-skill")
    assert_includes result, "# Valid Skill Instructions"
  end

  # Mock classes for testing
  class MockLoader
    def initialize(skills)
      @skills = skills
    end

    def list
      @skills
    end

    def find(name)
      @skills.find { |s| s.name == name }
    end
  end

  class MockDatabaseRecord
    attr_accessor :id, :name, :description, :content

    def initialize(attrs = {})
      attrs.each { |k, v| send("#{k}=", v) }
    end
  end
end
