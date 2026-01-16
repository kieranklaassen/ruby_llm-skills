# frozen_string_literal: true

require "test_helper"

class RubyLLMSkillsTest < ActiveSupport::TestCase
  test "gem is loaded in Rails" do
    assert defined?(RubyLLM::Skills), "RubyLLM::Skills should be defined"
  end

  test "default path is set to Rails app/skills" do
    expected = Rails.root.join("app/skills").to_s
    assert_equal expected, RubyLLM::Skills.default_path
  end

  test "loads skills from app/skills directory" do
    loader = RubyLLM::Skills.from_directory
    skills = loader.list

    assert skills.any?, "Should load at least one skill"
    assert skills.any? { |s| s.name == "greeting" }, "Should find greeting skill"
  end

  test "greeting skill has correct metadata" do
    loader = RubyLLM::Skills.from_directory
    greeting = loader.get("greeting")

    assert_not_nil greeting, "Should find greeting skill"
    assert_equal "greeting", greeting.name
    assert_match(/personalized greetings/i, greeting.description)
  end

  test "skill tool is available" do
    assert defined?(RubyLLM::Skills::SkillTool), "SkillTool should be defined"
  end
end
