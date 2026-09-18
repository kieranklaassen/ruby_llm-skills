# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"
require "rake"

class RubyLLM::Skills::Marketplace::TestRakeTasks < Minitest::Test
  include MarketplaceTestHelper

  TASKS = %w[add list plugins install update remove].map { |name| "skills:marketplaces:#{name}" }.freeze

  def setup
    super
    @rake = Rake::Application.new
    Rake.application = @rake
    load File.expand_path("../../../../lib/ruby_llm/skills/tasks/marketplaces.rake", __dir__)
    @previous = [RubyLLM::Skills::Marketplace.root, RubyLLM::Skills::Marketplace.lockfile]
    RubyLLM::Skills::Marketplace.root = scratch_root
    RubyLLM::Skills::Marketplace.lockfile = scratch_lockfile
  end

  def teardown
    RubyLLM::Skills::Marketplace.root, RubyLLM::Skills::Marketplace.lockfile = @previous
    super
  end

  def test_the_tasks_are_defined_without_a_rails_environment
    TASKS.each { |name| assert Rake::Task.task_defined?(name), "#{name} is not defined" }
    assert_equal [], Rake::Task["skills:marketplaces:list"].prerequisites
  end

  def test_the_plain_rakefile_entry_point_loads_every_task
    Rake.application = Rake::Application.new
    output, = capture_subprocess_io do
      system(Gem.ruby, "-I", File.expand_path("../../../../lib", __dir__), "-e",
        'require "rake"; Rake.application = Rake::Application.new; require "ruby_llm/skills/tasks"; puts Rake::Task.tasks.map(&:name).sort')
    end
    (TASKS + %w[skills:list skills:validate skills:show]).each { |name| assert_includes output.lines.map(&:strip), name }
  end

  def test_add_install_list_update_and_remove
    out = run_task("skills:marketplaces:add", marketplace_fixture_path("basic"))
    assert_match(/Added basic from .* at [0-9a-f]{12}/, out)

    out = run_task("skills:marketplaces:plugins", "basic")
    assert_includes out, "writing  -  available"
    assert_includes out, "notes  -  available"

    out = run_task("skills:marketplaces:install", "basic", "writing")
    assert_includes out, "+ basic/writing"
    refute_includes out, "notes"

    out = run_task("skills:marketplaces:install", "basic")
    assert_includes out, "+ basic/notes"
    assert_includes out, "= basic/writing"

    out = run_task("skills:marketplaces:list")
    assert_includes out, "basic  #{marketplace_fixture_path("basic")}"
    assert_includes out, "writing 1.2.0  skills: draft, help, nested-deep"

    out = run_task("skills:marketplaces:update")
    assert_includes out, "= basic/notes"

    out = run_task("skills:marketplaces:remove", "basic")
    assert_equal "Removed basic\n", out
    assert_includes run_task("skills:marketplaces:list"), "No marketplaces"
  end

  def test_install_aborts_when_a_plugin_fails
    run_task("skills:marketplaces:add", marketplace_fixture_path("broken"))
    error = assert_raises(SystemExit) { run_task("skills:marketplaces:install", "broken") }
    assert_equal "1 plugin(s) failed", error.message
  end

  def test_usage_errors_abort
    assert_raises(SystemExit) { run_task("skills:marketplaces:add") }
    assert_raises(SystemExit) { run_task("skills:marketplaces:remove") }
  end

  private

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    capture_io { task.invoke(*args) }.first
  end
end
