# frozen_string_literal: true

require "integration_helper"

class RubyLLM::Skills::TestSkillToolIntegration < Minitest::Test
  def setup
    @skills_path = File.join(fixtures_path, "skills")
    @commands_path = File.join(fixtures_path, "commands")
    @zip_path = File.join(fixtures_path, "skills.zip")
  end

  def test_with_skills_default
    VCR.use_cassette("with_skills_basic") do
      RubyLLM::Skills.default_path = @skills_path

      chat = RubyLLM.chat
      chat.with_skills

      response = chat.ask("I need help with the valid-skill, can you load it?")
      assert_includes response.content.downcase, "valid-skill"
    end
  end

  def test_with_skills_from_path
    VCR.use_cassette("slash_command_arguments") do
      chat = RubyLLM.chat
      chat.with_skills(@commands_path)

      response = chat.ask("/write-poem about robots in space")
      assert response.content.length > 50
    end
  end

  def test_with_skills_from_array
    VCR.use_cassette("composite_loader") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path, @commands_path)

      response = chat.ask("What skills and commands are available?")
      assert response.content.downcase.include?("valid-skill") ||
        response.content.downcase.include?("write-poem")
    end
  end

  def test_resource_loading
    VCR.use_cassette("resource_loading") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)

      response = chat.ask("Load the with-scripts skill and show scripts/helper.rb")
      assert_includes response.content.downcase, "helper"
    end
  end

  def test_skill_discovery
    VCR.use_cassette("skill_discovery") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)

      response = chat.ask("What skills are available?")
      assert_includes response.content.downcase, "valid-skill"
    end
  end

  def test_skills_with_other_tools
    VCR.use_cassette("skills_with_other_tools") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)
      chat.with_tool(AdditionTool)

      response = chat.ask("What is 2 + 2? Also, what skills are available?")
      assert response.content.include?("4") ||
        response.content.downcase.include?("valid-skill")
    end
  end

  class AdditionTool < RubyLLM::Tool
    description "Add two numbers together"
    param :a, desc: "First number"
    param :b, desc: "Second number"

    def execute(a:, b:)
      (a.to_f + b.to_f).to_s
    end
  end
end
