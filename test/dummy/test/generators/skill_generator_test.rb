# frozen_string_literal: true

require "test_helper"
require "generators/skill/skill_generator"

class SkillGeneratorTest < Rails::Generators::TestCase
  tests SkillGenerator
  destination Rails.root.join("tmp/generators")
  setup :prepare_destination

  test "generates skill directory and SKILL.md" do
    run_generator ["pdf-report"]

    assert_directory "app/skills/pdf-report"
    assert_file "app/skills/pdf-report/SKILL.md"
  end

  test "SKILL.md contains correct frontmatter" do
    run_generator ["pdf-report", "-d", "Generate PDF reports from data"]

    assert_file "app/skills/pdf-report/SKILL.md" do |content|
      assert_match(/^name: pdf-report$/, content)
      assert_match(/^description: "Generate PDF reports from data"$/, content)
    end
  end

  test "frontmatter round-trips values with YAML syntax in them" do
    description = %(Review PRs: flags "risky" diffs #security. Use when asked\\told to review)
    license = "MIT: see LICENSE #1"
    run_generator ["pr-review", "-d", description, "-l", license]

    assert_file "app/skills/pr-review/SKILL.md" do |content|
      metadata = RubyLLM::Skills::Parser.parse_string(content)
      assert_equal "pr-review", metadata["name"]
      assert_equal description, metadata["description"]
      assert_equal license, metadata["license"]
    end
  end

  test "default description parses" do
    run_generator ["pdf-report"]

    skill = RubyLLM::Skills.load(Rails.root.join("tmp/generators/app/skills/pdf-report").to_s)
    assert_equal "Description of what this skill does. Use when...", skill.description
    assert_predicate skill, :valid?
  end

  test "SKILL.md contains skill title" do
    run_generator ["data-export"]

    assert_file "app/skills/data-export/SKILL.md" do |content|
      assert_match(/# Data Export/, content)
    end
  end

  test "includes license when provided" do
    run_generator ["my-skill", "-l", "MIT"]

    assert_file "app/skills/my-skill/SKILL.md" do |content|
      assert_match(/^license: "MIT"$/, content)
    end
  end

  test "excludes license when not provided" do
    run_generator ["my-skill"]

    assert_file "app/skills/my-skill/SKILL.md" do |content|
      assert_no_match(/^license:/, content)
    end
  end

  test "creates scripts directory with --scripts" do
    run_generator ["my-skill", "--scripts"]

    assert_directory "app/skills/my-skill/scripts"
    assert_file "app/skills/my-skill/scripts/.keep"
  end

  test "creates references directory with --references" do
    run_generator ["my-skill", "--references"]

    assert_directory "app/skills/my-skill/references"
    assert_file "app/skills/my-skill/references/.keep"
  end

  test "creates assets directory with --assets" do
    run_generator ["my-skill", "--assets"]

    assert_directory "app/skills/my-skill/assets"
    assert_file "app/skills/my-skill/assets/.keep"
  end

  test "creates all optional directories" do
    run_generator ["full-skill", "--scripts", "--references", "--assets"]

    assert_directory "app/skills/full-skill/scripts"
    assert_directory "app/skills/full-skill/references"
    assert_directory "app/skills/full-skill/assets"
  end

  test "normalizes skill name with underscores" do
    run_generator ["my_skill_name"]

    assert_directory "app/skills/my-skill-name"
    assert_file "app/skills/my-skill-name/SKILL.md" do |content|
      assert_match(/^name: my-skill-name$/, content)
    end
  end

  test "normalizes skill name with mixed case" do
    run_generator ["MySkillName"]

    # CamelCase is converted to snake_case by Rails, then to kebab-case
    assert_directory "app/skills/my-skill-name"
    assert_file "app/skills/my-skill-name/SKILL.md" do |content|
      assert_match(/^name: my-skill-name$/, content)
    end
  end

  test "short aliases work for description and license" do
    run_generator ["test-skill", "-d", "Test description", "-l", "Apache-2.0"]

    assert_file "app/skills/test-skill/SKILL.md" do |content|
      assert_match(/description: "Test description"/, content)
      assert_match(/license: "Apache-2.0"/, content)
    end
  end
end
