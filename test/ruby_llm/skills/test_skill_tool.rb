# frozen_string_literal: true

require "test_helper"
require "ruby_llm/skills/skill_tool"
require "ruby_llm/skills/composite_loader"
require "json"
require "tmpdir"

class RubyLLM::Skills::TestSkillTool < Minitest::Test
  def setup
    @skills_path = File.join(fixtures_path, "skills")
    @loader = RubyLLM::Skills::FilesystemLoader.new(@skills_path)
    @tool = RubyLLM::Skills::SkillTool.new(@loader)
  end

  def test_initialize_with_loader
    tool = RubyLLM::Skills::SkillTool.new(@loader)
    assert_equal @loader, tool.loader
  end

  def test_name_returns_skill
    assert_equal "skill", @tool.name
  end

  def test_tool_name_returns_skill
    assert_equal "skill", RubyLLM::Skills::SkillTool.tool_name
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
    mock_skill = RubyLLM::Skills::Skill.new(
      path: "database:test",
      metadata: {
        "name" => "test-skill",
        "description" => "Test <with> special & \"chars'"
      }
    )
    mock_loader = MockLoader.new([mock_skill])
    tool = RubyLLM::Skills::SkillTool.new(mock_loader)

    description = tool.description
    assert_includes description, "&lt;with&gt;"
    assert_includes description, "&amp;"
    assert_includes description, "&quot;"
    assert_includes description, "&apos;"
  end

  def test_parameters_returns_json_schema
    params = @tool.parameters_schema

    assert_equal "object", params["type"]
    assert params["properties"].key?("command")
    assert_equal "string", params["properties"]["command"]["type"]
    assert_includes params["required"], "command"
  end

  def test_call_returns_skill_content
    result = @tool.call(command: "valid-skill")

    assert_includes result, "# Skill: valid-skill"
    assert_includes result, "# Valid Skill Instructions"
    assert_includes result, "This is a valid skill used for testing"
  end

  def test_call_returns_error_for_unknown_skill
    result = @tool.call(command: "nonexistent-skill")

    assert_includes result, "Skill 'nonexistent-skill' not found"
    assert_includes result, "Available skills:"
  end

  def test_execute_is_alias_for_call
    result = @tool.execute(command: "valid-skill")

    assert_includes result, "# Skill: valid-skill"
  end

  def test_call_with_unknown_keyword_returns_error_hash
    result = @tool.call(command: "valid-skill", bogus: "value")

    assert_kind_of Hash, result
    assert_includes result[:error], "unknown keyword: bogus"
  end

  def test_call_without_command_returns_error_hash
    result = @tool.call(arguments: "about robots")

    assert_kind_of Hash, result
    assert_includes result[:error], "missing keyword: command"
  end

  def test_call_includes_scripts_section_when_present
    result = @tool.call(command: "with-scripts")

    assert_includes result, "## Available Scripts"
    assert_includes result, "helper.rb"
    assert_includes result, "setup.sh"
  end

  def test_call_includes_references_section_when_present
    result = @tool.call(command: "with-all-resources")

    assert_includes result, "## Available References"
    assert_includes result, "guide.md"
  end

  def test_call_includes_assets_section_when_present
    result = @tool.call(command: "with-all-resources")

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
    empty_loader = RubyLLM::Skills::FilesystemLoader.new("/nonexistent/path")
    tool = RubyLLM::Skills::SkillTool.new(empty_loader)

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
    loader = RubyLLM::Skills::DatabaseLoader.new(records)
    tool = RubyLLM::Skills::SkillTool.new(loader)

    description = tool.description
    assert_includes description, "<name>db-skill</name>"

    result = tool.call(command: "db-skill")
    assert_includes result, "# Database Skill Content"
  end

  def test_works_with_composite_loader
    loader1 = RubyLLM::Skills::FilesystemLoader.new(@skills_path)
    composite = RubyLLM::Skills::CompositeLoader.new([loader1])
    tool = RubyLLM::Skills::SkillTool.new(composite)

    description = tool.description
    assert_includes description, "valid-skill"

    result = tool.call(command: "valid-skill")
    assert_includes result, "# Valid Skill Instructions"
  end

  # Resource loading tests

  def test_parameters_include_optional_resource
    params = @tool.parameters_schema

    assert params["properties"].key?("resource")
    assert_equal "string", params["properties"]["resource"]["type"]
    refute_includes params["required"], "resource"
  end

  def test_call_with_resource_loads_script
    result = @tool.call(command: "with-scripts", resource: "scripts/helper.rb")

    assert_includes result, "# Resource: scripts/helper.rb"
    assert_includes result, "def helper_method"
    assert_includes result, "Hello from helper"
  end

  def test_call_with_resource_loads_reference
    result = @tool.call(command: "with-all-resources", resource: "references/guide.md")

    assert_includes result, "# Resource: references/guide.md"
    assert_includes result, "# Reference Guide"
  end

  def test_call_with_resource_loads_asset
    result = @tool.call(command: "with-all-resources", resource: "assets/template.txt")

    assert_includes result, "# Resource: assets/template.txt"
  end

  def test_call_with_nonexistent_resource_returns_error
    result = @tool.call(command: "with-scripts", resource: "scripts/nonexistent.rb")

    assert_includes result, "Resource 'scripts/nonexistent.rb' not found"
    assert_includes result, "Available:"
  end

  def test_call_with_path_traversal_returns_error
    result = @tool.call(command: "with-scripts", resource: "../../../etc/passwd")

    assert_includes result, "Invalid resource path"
  end

  def test_call_with_absolute_path_returns_error
    result = @tool.call(command: "with-scripts", resource: "/etc/passwd")

    assert_includes result, "Invalid resource path"
  end

  def test_call_with_binary_resource_returns_message_instead_of_bytes
    with_skill("assets/logo.png" => "\x89PNG\r\n\x1A\n\x00\xFF\xD8".b) do |tool|
      result = tool.call(command: "tmp-skill", resource: "assets/logo.png")

      assert_equal "Resource 'assets/logo.png' is not a text file and cannot be loaded as text", result
      assert JSON.generate(result)
    end
  end

  def test_call_with_utf8_resource_under_non_utf8_default_external
    with_skill("references/menu.md" => "café ☕\n") do |tool|
      result = with_default_external(Encoding::US_ASCII) do
        tool.call(command: "tmp-skill", resource: "references/menu.md")
      end

      assert_predicate result, :valid_encoding?
      assert_includes result, "café ☕"
    end
  end

  def test_call_with_resource_on_virtual_skill_returns_error
    require "ruby_llm/skills/database_loader"

    records = [
      MockDatabaseRecord.new(
        id: 1,
        name: "db-skill",
        description: "A database skill",
        content: "# Database Skill Content"
      )
    ]
    loader = RubyLLM::Skills::DatabaseLoader.new(records)
    tool = RubyLLM::Skills::SkillTool.new(loader)

    result = tool.call(command: "db-skill", resource: "scripts/test.rb")
    assert_includes result, "Cannot load resources from virtual skills"
  end

  def test_execute_with_resource_keyword_arg
    result = @tool.execute(command: "with-scripts", resource: "scripts/helper.rb")

    assert_includes result, "# Resource: scripts/helper.rb"
    assert_includes result, "def helper_method"
  end

  def test_skill_response_includes_resource_loading_hint
    result = @tool.call(command: "with-scripts")

    assert_includes result, "To load a resource, call this tool again with resource parameter"
    assert_includes result, "scripts/"
  end

  def test_skill_response_shows_full_resource_paths
    result = @tool.call(command: "with-all-resources")

    assert_includes result, "scripts/main.rb"
    assert_includes result, "references/guide.md"
    assert_includes result, "assets/template.txt"
  end

  def test_skill_response_lists_nested_resources_by_loadable_path
    files = {
      "scripts/lib/util.rb" => "def util_method; end\n",
      "references/guide.md" => "# Guide\n",
      "references/api/guide.md" => "# API Guide\n",
      "assets/img/readme.txt" => "Images\n"
    }
    with_skill(files) do |tool|
      listed = tool.call(command: "tmp-skill").lines.map(&:chomp)

      files.each_key { |path| assert_equal 1, listed.count("- #{path}"), "#{path} is not listed once" }
      refute_includes listed, "- scripts/util.rb"

      assert_includes tool.call(command: "tmp-skill", resource: "scripts/lib/util.rb"), "def util_method"
      assert_includes tool.call(command: "tmp-skill", resource: "references/api/guide.md"), "# API Guide"
    end
  end

  # Arguments tests

  def test_parameters_include_optional_arguments
    params = @tool.parameters_schema

    assert params["properties"].key?("arguments")
    assert_equal "string", params["properties"]["arguments"]["type"]
    refute_includes params["required"], "arguments"
  end

  def test_call_with_arguments_includes_arguments_in_response
    result = @tool.call(command: "valid-skill", arguments: "about robots")

    assert_includes result, "# Skill: valid-skill"
    assert_includes result, "# Arguments: about robots"
  end

  def test_call_without_arguments_omits_arguments_section
    result = @tool.call(command: "valid-skill")

    refute_includes result, "# Arguments:"
  end

  def test_execute_with_arguments_keyword
    result = @tool.execute(command: "valid-skill", arguments: "some topic")

    assert_includes result, "# Arguments: some topic"
  end

  def test_description_mentions_arguments
    description = @tool.description

    assert_includes description, "arguments"
  end

  private

  def with_skill(files)
    Dir.mktmpdir do |dir|
      root = File.join(dir, "tmp-skill")
      files = {"SKILL.md" => "---\nname: tmp-skill\ndescription: A temporary skill\n---\nBody\n"}.merge(files)
      files.each do |relative, content|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, content)
      end
      yield RubyLLM::Skills::SkillTool.new(RubyLLM::Skills::FilesystemLoader.new(dir)), root
    end
  end

  def with_default_external(encoding)
    previous = Encoding.default_external
    silence_warnings { Encoding.default_external = encoding }
    yield
  ensure
    silence_warnings { Encoding.default_external = previous }
  end

  def silence_warnings
    verbose, $VERBOSE = $VERBOSE, nil
    yield
  ensure
    $VERBOSE = verbose
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
