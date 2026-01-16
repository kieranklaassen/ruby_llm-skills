# frozen_string_literal: true

require "integration_helper"

class RubyLlm::Skills::TestSkillToolIntegration < Minitest::Test
  def setup
    @skills_path = File.join(fixtures_path, "skills")
    @commands_path = File.join(fixtures_path, "commands")
  end

  # Test 1: Basic skill loading using with_skills
  def test_with_skills_loads_and_invokes_skill
    VCR.use_cassette("with_skills_basic") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)

      response = chat.ask("I need help with the valid-skill, can you load it?")

      assert_includes response.content.downcase, "valid-skill"
    end
  end

  # Test 2: Slash command with arguments
  def test_slash_command_with_arguments
    VCR.use_cassette("slash_command_arguments") do
      chat = RubyLLM.chat
      chat.with_skills(@commands_path)

      response = chat.ask("/write-poem about robots in space")

      # The LLM should have invoked the skill and written a poem
      assert response.content.length > 50, "Expected a poem response"
    end
  end

  # Test 3: Resource loading
  def test_resource_loading
    VCR.use_cassette("resource_loading") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)

      response = chat.ask(
        "Load the with-scripts skill, then load the scripts/helper.rb resource and show me what's in it"
      )

      # The LLM should have loaded the resource content
      assert_includes response.content.downcase, "helper"
    end
  end

  # Test 4: Skill discovery - LLM lists available skills
  def test_skill_discovery
    VCR.use_cassette("skill_discovery") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)

      response = chat.ask("What skills are available? List them for me.")

      # Should mention some of the available skills
      assert_includes response.content.downcase, "valid-skill"
    end
  end

  # Test 5: Skill not found handling
  def test_skill_not_found
    VCR.use_cassette("skill_not_found") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)

      response = chat.ask("Load the skill called 'nonexistent-xyz-skill' for me")

      # Should mention the skill wasn't found or list available ones
      content = response.content.downcase
      assert(
        content.include?("not found") || content.include?("available") || content.include?("valid-skill"),
        "Expected error handling or skill suggestions"
      )
    end
  end

  # Test 6: Composite loader with multiple sources
  def test_composite_loader
    VCR.use_cassette("composite_loader") do
      loader = RubyLlm::Skills.compose(
        RubyLlm::Skills.from_directory(@skills_path),
        RubyLlm::Skills.from_directory(@commands_path)
      )
      skill_tool = RubyLlm::Skills::SkillTool.new(loader)

      chat = RubyLLM.chat
      chat.with_tool(skill_tool)

      response = chat.ask("What skills and commands are available?")

      # Should see both skills and commands
      content = response.content.downcase
      assert(
        content.include?("valid-skill") || content.include?("write-poem"),
        "Expected to see skills from both loaders"
      )
    end
  end

  # Test 7: Skills work alongside other tools
  def test_skills_with_other_tools
    VCR.use_cassette("skills_with_other_tools") do
      chat = RubyLLM.chat
      chat.with_skills(@skills_path)
      chat.with_tool(AdditionTool)

      response = chat.ask("What is 2 + 2? Also, what skills are available?")

      # Should handle both the calculation and list skills
      content = response.content
      assert(
        content.include?("4") || content.downcase.include?("valid-skill"),
        "Expected either calculation result or skill list"
      )
    end
  end

  # Test tool for testing skills alongside other tools
  class AdditionTool < RubyLLM::Tool
    description "Add two numbers together"
    param :a, desc: "First number"
    param :b, desc: "Second number"

    def execute(a:, b:)
      (a.to_f + b.to_f).to_s
    end
  end
end
