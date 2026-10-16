# frozen_string_literal: true

require "test_helper"
require "rake"

class RakeTasksTest < ActiveSupport::TestCase
  setup do
    @previous = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
  end

  teardown do
    Rake.application = @previous
  end

  test "every skills task loads the Rails environment first" do
    tasks = Rake::Task.tasks.select { |task| task.name.start_with?("skills:") }

    assert_operator tasks.size, :>=, 9
    tasks.each do |task|
      assert_equal ["environment"], task.prerequisites, "#{task.name} does not load the environment"
    end
  end
end
