# frozen_string_literal: true

require "test_helper"

class RubyLLM::Skills::TestChatExtensions < Minitest::Test
  def setup
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "test-key")
    end
    @skills_path = File.join(fixtures_path, "skills")
    @commands_path = File.join(fixtures_path, "commands")
  end

  def test_with_skills_registers_skill_tool_under_skill_key
    chat = RubyLLM.chat(model: "gpt-5-nano").with_skills(@skills_path)

    assert_kind_of RubyLLM::Skills::SkillTool, chat.tools.fetch(:skill)
    assert_includes chat.tools.fetch(:skill).description, "<name>valid-skill</name>"
  end

  def test_with_skills_returns_chat_for_chaining
    chat = RubyLLM.chat(model: "gpt-5-nano")

    assert_same chat, chat.with_skills(@skills_path)
  end

  def test_second_with_skills_replaces_skill_tool
    chat = RubyLLM.chat(model: "gpt-5-nano").with_skills(@skills_path)
    chat.with_skills(@commands_path)

    skill_tools = chat.tools.select { |_name, tool| tool.is_a?(RubyLLM::Skills::SkillTool) }
    assert_equal 1, skill_tools.size

    description = chat.tools.fetch(:skill).description
    assert_includes description, "<name>write-poem</name>"
    refute_includes description, "<name>valid-skill</name>"
  end

  def test_with_skills_only_filters_through_filtered_loader
    chat = RubyLLM.chat(model: "gpt-5-nano").with_skills(@skills_path, only: ["valid-skill"])
    skill_tool = chat.tools.fetch(:skill)

    assert_kind_of RubyLLM::Skills::FilteredLoader, skill_tool.loader
    assert_includes skill_tool.description, "<name>valid-skill</name>"
    refute_includes skill_tool.description, "<name>with-scripts</name>"
  end

  def test_with_skills_combines_multiple_sources
    chat = RubyLLM.chat(model: "gpt-5-nano").with_skills(@skills_path, @commands_path)
    description = chat.tools.fetch(:skill).description

    assert_includes description, "<name>valid-skill</name>"
    assert_includes description, "<name>write-poem</name>"
  end

  def test_with_skills_accepts_loader_instance
    loader = RubyLLM::Skills.from_directory(@skills_path)
    chat = RubyLLM.chat(model: "gpt-5-nano").with_skills(loader)

    assert_same loader, chat.tools.fetch(:skill).loader
  end

  def test_with_skills_rejects_invalid_source
    chat = RubyLLM.chat(model: "gpt-5-nano")

    error = assert_raises(ArgumentError) { chat.with_skills(Object.new) }
    assert_includes error.message, "Invalid skill source"
  end

  def test_with_skills_coexists_with_other_tools
    other_tool = Class.new(RubyLLM::Tool) do
      def self.tool_name
        "other"
      end

      description "Another tool"

      def execute
        "ok"
      end
    end

    chat = RubyLLM.chat(model: "gpt-5-nano").with_tools(other_tool).with_skills(@skills_path)

    assert_equal %i[other skill], chat.tools.keys.sort
  end
end
