# frozen_string_literal: true

require "test_helper"
require "rake"
require "tmpdir"

class RubyLLM::Skills::TestRakeTasks < Minitest::Test
  def setup
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake::Task.define_task(:environment)
    load File.expand_path("../../../lib/ruby_llm/skills/tasks/skills.rake", __dir__)
    @previous = RubyLLM::Skills.default_path
    RubyLLM::Skills.default_path = File.join(fixtures_path, "skills")
  end

  def teardown
    RubyLLM::Skills.default_path = @previous
  end

  def test_list_prints_every_skill
    out = run_task("skills:list")

    assert_includes out, "✓ valid-skill"
    assert_includes out, "A valid test skill for unit testing"
    assert_includes out, "with-scripts"
  end

  def test_list_reports_an_empty_directory
    RubyLLM::Skills.default_path = File.join(fixtures_path, "nonexistent")

    assert_equal "No skills found in #{RubyLLM::Skills.default_path}\n", run_task("skills:list")
  end

  def test_validate_reports_valid_and_invalid_skills
    out = run_task("skills:validate") { |invoke| assert_raises(SystemExit, &invoke) }

    assert_includes out, "✓ valid-skill"
    assert_match(/^✗ /, out)
    assert_match(/\d+ valid, \d+ invalid/, out)
  end

  def test_show_prints_skill_details
    out = run_task("skills:show", "with-all-resources")

    assert_includes out, "Name: with-all-resources"
    assert_includes out, "Path: #{skill_fixture_path("with-all-resources")}"
    assert_includes out, "Scripts:"
    assert_includes out, "  - scripts/main.rb"
    assert_includes out, "  - references/guide.md"
    assert_includes out, "  - assets/template.txt"
  end

  def test_show_lists_nested_resources_by_relative_path
    Dir.mktmpdir do |dir|
      {"SKILL.md" => "---\nname: nested\ndescription: Nested resources\n---\nBody\n",
       "scripts/lib/util.rb" => "", "references/guide.md" => "", "references/api/guide.md" => ""}.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(dir, "nested", path)))
        File.write(File.join(dir, "nested", path), content)
      end
      RubyLLM::Skills.default_path = dir

      listed = run_task("skills:show", "nested").lines.map(&:chomp)

      assert_includes listed, "  - scripts/lib/util.rb"
      assert_includes listed, "  - references/api/guide.md"
      assert_equal 1, listed.count("  - references/guide.md")
    end
  end

  private

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    invoke = -> { task.invoke(*args) }
    capture_io { block_given? ? yield(invoke) : invoke.call }.first
  end
end
