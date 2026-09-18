# frozen_string_literal: true

# Loads the gem's Rake tasks outside Rails (the Railtie loads them under Rails):
#
#   # Rakefile
#   require "ruby_llm/skills/tasks"
#
require "ruby_llm/skills"

load File.expand_path("tasks/skills.rake", __dir__)
load File.expand_path("tasks/marketplaces.rake", __dir__)
