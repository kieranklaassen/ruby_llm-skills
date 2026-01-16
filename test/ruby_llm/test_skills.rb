# frozen_string_literal: true

require "test_helper"

class RubyLLM::TestSkills < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::RubyLLM::Skills::VERSION
  end

  def test_module_exists
    assert defined?(RubyLLM::Skills)
  end
end
