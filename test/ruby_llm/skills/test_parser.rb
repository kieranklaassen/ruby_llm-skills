# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RubyLLM::Skills::TestParser < Minitest::Test
  def test_parse_file_extracts_frontmatter
    path = File.join(skill_fixture_path("valid-skill"), "SKILL.md")
    metadata = RubyLLM::Skills::Parser.parse_file(path)

    assert_equal "valid-skill", metadata["name"]
    assert_equal "A valid test skill for unit testing", metadata["description"]
    assert_equal "MIT", metadata["license"]
    assert_equal "RubyLLM 1.0+", metadata["compatibility"]
  end

  def test_parse_file_extracts_metadata_hash
    path = File.join(skill_fixture_path("valid-skill"), "SKILL.md")
    metadata = RubyLLM::Skills::Parser.parse_file(path)

    assert_equal "test-org", metadata["metadata"]["author"]
    assert_equal "1.0", metadata["metadata"]["version"]
  end

  def test_parse_file_extracts_allowed_tools
    path = File.join(skill_fixture_path("valid-skill"), "SKILL.md")
    metadata = RubyLLM::Skills::Parser.parse_file(path)

    assert_equal "Bash Read", metadata["allowed-tools"]
  end

  def test_parse_file_raises_on_missing_file
    error = assert_raises(RubyLLM::Skills::ParseError) do
      RubyLLM::Skills::Parser.parse_file("/nonexistent/path/SKILL.md")
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

    metadata = RubyLLM::Skills::Parser.parse_string(content)
    assert_equal "test-skill", metadata["name"]
    assert_equal "Test description", metadata["description"]
  end

  def test_parse_string_raises_on_missing_frontmatter
    content = "# No frontmatter here"

    error = assert_raises(RubyLLM::Skills::ParseError) do
      RubyLLM::Skills::Parser.parse_string(content)
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

    error = assert_raises(RubyLLM::Skills::ParseError) do
      RubyLLM::Skills::Parser.parse_string(content)
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

    body = RubyLLM::Skills::Parser.extract_body(content)
    assert_equal "# Skill Instructions\n\nThis is the body content.", body
  end

  def test_extract_body_returns_empty_string_for_invalid_content
    content = "No frontmatter"
    body = RubyLLM::Skills::Parser.extract_body(content)
    assert_equal "", body
  end

  def test_parse_string_handles_empty_frontmatter
    content = <<~SKILL
      ---

      ---
      # Just content
    SKILL

    metadata = RubyLLM::Skills::Parser.parse_string(content)
    assert_equal({}, metadata)
  end

  def test_parses_crlf_line_endings
    content = "---\r\nname: crlf-skill\r\ndescription: Saved on Windows\r\n---\r\n# Heading\r\n\r\nBody\r\n"

    metadata = RubyLLM::Skills::Parser.parse_string(content)
    assert_equal "crlf-skill", metadata["name"]
    assert_equal "Saved on Windows", metadata["description"]
    assert_equal "# Heading\r\n\r\nBody", RubyLLM::Skills::Parser.extract_body(content)
  end

  def test_parses_a_leading_byte_order_mark
    content = "\uFEFF---\nname: bom-skill\ndescription: Saved with a BOM\n---\n# Heading\n"

    assert_equal "bom-skill", RubyLLM::Skills::Parser.parse_string(content)["name"]
    assert_equal "# Heading", RubyLLM::Skills::Parser.extract_body(content)
    assert_equal "bom-skill", RubyLLM::Skills::Parser.parse_string(content.b)["name"]
  end

  def test_parses_trailing_spaces_after_the_fences
    content = "--- \nname: spaced\ndescription: Fences with trailing spaces\n---\t \n# Heading\n"

    assert_equal "spaced", RubyLLM::Skills::Parser.parse_string(content)["name"]
    assert_equal "# Heading", RubyLLM::Skills::Parser.extract_body(content)
  end

  def test_parse_file_reads_a_crlf_file_with_a_byte_order_mark
    Dir.mktmpdir do |dir|
      path = File.join(dir, "SKILL.md")
      File.binwrite(path, "\uFEFF---\r\nname: windows\r\ndescription: CRLF and BOM\r\n---\r\nBody\r\n")

      assert_equal({"name" => "windows", "description" => "CRLF and BOM"}, RubyLLM::Skills::Parser.parse_file(path))
    end
  end
end
