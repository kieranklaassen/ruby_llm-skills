# frozen_string_literal: true

require "test_helper"

class DatabaseSkillsTest < ActiveSupport::TestCase
  setup do
    # Create test skills in the database
    @email_skill = Skill.create!(
      name: "email-composer",
      description: "Compose professional emails. Use when asked to write or draft emails.",
      content: <<~MARKDOWN
        # Email Composer

        Write professional emails for any occasion.

        ## Instructions

        1. Identify the tone (formal, casual, urgent)
        2. Structure with greeting, body, closing
        3. Review for clarity
      MARKDOWN
    )

    @code_review_skill = Skill.create!(
      name: "code-review",
      description: "Review code for best practices. Use when asked to review or critique code.",
      content: <<~MARKDOWN
        # Code Review

        Perform thorough code reviews.

        ## Checklist

        - [ ] Check for bugs
        - [ ] Verify naming conventions
        - [ ] Look for performance issues
      MARKDOWN
    )
  end

  teardown do
    Skill.delete_all
  end

  test "loads skills from database records" do
    loader = RubyLLM::Skills.from_database(Skill.all)
    skills = loader.list

    assert_equal 2, skills.size
    assert skills.any? { |s| s.name == "email-composer" }
    assert skills.any? { |s| s.name == "code-review" }
  end

  test "finds skill by name from database" do
    loader = RubyLLM::Skills.from_database(Skill.all)
    skill = loader.get("email-composer")

    assert_not_nil skill
    assert_equal "email-composer", skill.name
    assert_match(/professional emails/i, skill.description)
  end

  test "skill content is accessible" do
    loader = RubyLLM::Skills.from_database(Skill.all)
    skill = loader.get("code-review")

    assert_match(/Code Review/, skill.content)
    assert_match(/Check for bugs/, skill.content)
  end

  test "loads skills from scoped relation" do
    # Only load skills with 'email' in the name
    loader = RubyLLM::Skills.from_database(Skill.where("name LIKE ?", "%email%"))
    skills = loader.list

    assert_equal 1, skills.size
    assert_equal "email-composer", skills.first.name
  end

  test "combines database and filesystem skills" do
    db_loader = RubyLLM::Skills.from_database(Skill.all)
    fs_loader = RubyLLM::Skills.from_directory

    composite = RubyLLM::Skills.compose(fs_loader, db_loader)
    skills = composite.list

    # Should have greeting (from filesystem) + 2 from database
    assert skills.size >= 3
    assert skills.any? { |s| s.name == "greeting" }
    assert skills.any? { |s| s.name == "email-composer" }
    assert skills.any? { |s| s.name == "code-review" }
  end

  test "database loader provides expected interface" do
    loader = RubyLLM::Skills.from_database(Skill.all)

    # Verify loader provides expected interface
    assert_respond_to loader, :list
    assert_respond_to loader, :get
    assert_respond_to loader, :find
    assert_respond_to loader, :exists?
    assert_respond_to loader, :reload!
  end

  test "exists? returns true for existing skills" do
    loader = RubyLLM::Skills.from_database(Skill.all)

    assert loader.exists?("email-composer")
    assert loader.exists?("code-review")
    assert_not loader.exists?("nonexistent-skill")
  end

  test "reload! clears cached skills" do
    loader = RubyLLM::Skills.from_database(Skill.all)

    # Load skills initially
    assert_equal 2, loader.list.size

    # Add a new skill
    Skill.create!(
      name: "new-skill",
      description: "A new skill",
      content: "# New Skill"
    )

    # Without reload, still shows 2
    assert_equal 2, loader.list.size

    # After reload, shows 3
    loader.reload!
    assert_equal 3, loader.list.size
  end
end
