# frozen_string_literal: true

require "test_helper"

class RubyLlm::Skills::TestParser < Minitest::Test
  def test_parse_file_extracts_frontmatter
    path = File.join(skill_fixture_path("valid-skill"), "SKILL.md")
    metadata = RubyLlm::Skills::Parser.parse_file(path)

    assert_equal "valid-skill", metadata["name"]
    assert_equal "A valid test skill for unit testing", metadata["description"]
    assert_equal "MIT", metadata["license"]
    assert_equal "RubyLLM 1.0+", metadata["compatibility"]
  end

  def test_parse_file_extracts_metadata_hash
    path = File.join(skill_fixture_path("valid-skill"), "SKILL.md")
    metadata = RubyLlm::Skills::Parser.parse_file(path)

    assert_equal "test-org", metadata["metadata"]["author"]
    assert_equal "1.0", metadata["metadata"]["version"]
  end

  def test_parse_file_extracts_allowed_tools
    path = File.join(skill_fixture_path("valid-skill"), "SKILL.md")
    metadata = RubyLlm::Skills::Parser.parse_file(path)

    assert_equal "Bash Read", metadata["allowed-tools"]
  end

  def test_parse_file_raises_on_missing_file
    error = assert_raises(RubyLlm::Skills::ParseError) do
      RubyLlm::Skills::Parser.parse_file("/nonexistent/path/SKILL.md")
    end
    assert_match(/File not found/, error.message)
  end

  def test_parse_string_extracts_frontmatter
    content = <<~SKILL
      ---
      name: test-skill
      description: Test description
      ---
      # Content here
    SKILL

    metadata = RubyLlm::Skills::Parser.parse_string(content)
    assert_equal "test-skill", metadata["name"]
    assert_equal "Test description", metadata["description"]
  end

  def test_parse_string_raises_on_missing_frontmatter
    content = "# No frontmatter here"

    error = assert_raises(RubyLlm::Skills::ParseError) do
      RubyLlm::Skills::Parser.parse_string(content)
    end
    assert_match(/Missing YAML frontmatter/, error.message)
  end

  def test_parse_string_raises_on_invalid_yaml
    content = <<~SKILL
      ---
      name: [invalid yaml
      ---
      # Content
    SKILL

    error = assert_raises(RubyLlm::Skills::ParseError) do
      RubyLlm::Skills::Parser.parse_string(content)
    end
    assert_match(/Invalid YAML frontmatter/, error.message)
  end

  def test_extract_body_returns_content_after_frontmatter
    content = <<~SKILL
      ---
      name: test-skill
      description: Test
      ---
      # Skill Instructions

      This is the body content.
    SKILL

    body = RubyLlm::Skills::Parser.extract_body(content)
    assert_equal "# Skill Instructions\n\nThis is the body content.", body
  end

  def test_extract_body_returns_empty_string_for_invalid_content
    content = "No frontmatter"
    body = RubyLlm::Skills::Parser.extract_body(content)
    assert_equal "", body
  end

  def test_parse_string_handles_empty_frontmatter
    content = <<~SKILL
      ---

      ---
      # Just content
    SKILL

    metadata = RubyLlm::Skills::Parser.parse_string(content)
    assert_equal({}, metadata)
  end
end
