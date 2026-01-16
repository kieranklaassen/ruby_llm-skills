# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby_llm/skills"

require "minitest/autorun"

module FixturesHelper
  def fixtures_path
    File.expand_path("fixtures", __dir__)
  end

  def skill_fixture_path(name)
    File.join(fixtures_path, "skills", name)
  end
end

class Minitest::Test
  include FixturesHelper
end
