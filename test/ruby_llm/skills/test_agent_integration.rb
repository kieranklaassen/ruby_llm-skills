# frozen_string_literal: true

require "integration_helper"

class RubyLLM::Skills::TestAgentIntegration < Minitest::Test
  def test_agent_with_skills_can_discover_and_use_skills
    skills_path = File.join(fixtures_path, "skills")
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-5-nano"
      skills skills_path
    end

    VCR.use_cassette("with_skills_basic") do
      chat = agent_class.chat
      response = chat.ask("I need help with the valid-skill, can you load it?")
      assert_includes response.content.downcase, "valid-skill"
    end
  end
end
