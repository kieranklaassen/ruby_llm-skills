# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create do |t|
  t.test_globs = ["test/ruby_llm/**/test_*.rb"]
end

require "standard/rake"

desc "Run Rails integration tests"
task :test_rails do
  Dir.chdir("test/dummy") do
    Bundler.with_unbundled_env do
      sh "bundle exec rails test"
    end
  end
end

desc "Run all tests (unit + Rails integration)"
task test_all: %i[test test_rails]

task default: %i[test standard]
