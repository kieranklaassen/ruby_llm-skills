# frozen_string_literal: true

require "test_helper"

class RubyLLM::Skills::TestAgentExtensions < Minitest::Test
  def setup
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "test-key")
    end
    @skills_path = File.join(fixtures_path, "skills")
  end

  # --- Class-level DSL ---

  def test_skills_macro_stores_sources
    agent_class = Class.new(RubyLLM::Agent) { skills "app/skills" }
    config = agent_class.skills

    assert_equal ["app/skills"], config[:sources]
    assert_nil config[:only]
  end

  def test_skills_macro_with_only_filter
    agent_class = Class.new(RubyLLM::Agent) do
      skills "app/skills", only: [:valid_skill]
    end

    assert_equal [:valid_skill], agent_class.skills[:only]
  end

  def test_skills_macro_with_multiple_sources
    agent_class = Class.new(RubyLLM::Agent) do
      skills "app/skills", "app/commands"
    end

    assert_equal ["app/skills", "app/commands"], agent_class.skills[:sources]
  end

  def test_skills_macro_with_block
    agent_class = Class.new(RubyLLM::Agent) do
      skills { ["dynamic/path"] }
    end

    assert agent_class.skills[:sources].is_a?(Proc)
  end

  def test_skills_no_args_is_getter
    agent_class = Class.new(RubyLLM::Agent)
    config = agent_class.skills

    assert_nil config[:sources]
    assert_nil config[:only]
  end

  # --- Inheritance ---

  def test_skills_inherited_by_subclass
    parent = Class.new(RubyLLM::Agent) do
      skills "app/skills", only: [:valid_skill]
    end
    child = Class.new(parent)

    assert_equal ["app/skills"], child.skills[:sources]
    assert_equal [:valid_skill], child.skills[:only]
  end

  def test_child_can_override_parent_skills
    parent = Class.new(RubyLLM::Agent) { skills "parent/skills" }
    child = Class.new(parent) { skills "child/skills" }

    assert_equal ["child/skills"], child.skills[:sources]
    assert_equal ["parent/skills"], parent.skills[:sources]
  end

  # --- Combined with tools ---

  def test_skills_and_tools_coexist
    tool_class = Class.new(RubyLLM::Tool) do
      description "Test tool"

      def execute
        "ok"
      end
    end

    agent_class = Class.new(RubyLLM::Agent) do
      tools tool_class
      skills "app/skills"
    end

    assert_equal [tool_class], agent_class.tools
    assert_equal ["app/skills"], agent_class.skills[:sources]
  end

  # --- apply_configuration integration ---

  def test_agent_chat_registers_skill_tool
    path = @skills_path
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-5-nano"
      skills path
    end

    chat = agent_class.chat
    assert chat.tools.key?(:skill), "Expected :skill tool to be registered"
  end

  def test_agent_new_registers_skill_tool
    path = @skills_path
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-5-nano"
      skills path
    end

    agent = agent_class.new
    assert agent.chat.tools.key?(:skill)
  end

  def test_agent_without_skills_has_no_skill_tool
    agent_class = Class.new(RubyLLM::Agent) { model "gpt-5-nano" }
    chat = agent_class.chat

    refute chat.tools.key?(:skill)
  end

  def test_agent_applies_only_filter
    path = @skills_path
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-5-nano"
      skills path, only: ["valid-skill"]
    end

    chat = agent_class.chat
    description = chat.tools.fetch(:skill).description

    assert_includes description, "<name>valid-skill</name>"
    refute_includes description, "<name>with-scripts</name>"
  end

  def test_block_based_skills_can_access_runtime_inputs
    path = @skills_path
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-5-nano"
      inputs :skill_source
      skills { [skill_source] }
    end

    chat = agent_class.chat(skill_source: path)
    assert chat.tools.key?(:skill)
  end

  def test_block_based_skills_can_access_runtime_chat
    path = @skills_path
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-5-nano"
      inputs :skill_source
      skills do
        raise "runtime chat missing tools accessor" unless chat.respond_to?(:tools)
        [skill_source]
      end
    end

    chat = agent_class.chat(skill_source: path)
    assert chat.tools.key?(:skill)
  end

  # --- Instance-level with_skills ---

  def test_instance_with_skills_adds_to_chat
    agent_class = Class.new(RubyLLM::Agent) { model "gpt-5-nano" }
    agent = agent_class.new

    result = agent.with_skills(@skills_path)

    assert_equal agent, result
    assert agent.chat.tools.key?(:skill)
  end
end
