# frozen_string_literal: true

module RubyLlm
  module Skills
    # Base error class for all skills-related errors.
    # Rescue this to catch any error from the gem.
    class Error < StandardError; end

    # Raised when a skill has invalid structure or content.
    class InvalidSkillError < Error; end

    # Raised when a requested skill cannot be found.
    class NotFoundError < Error; end

    # Raised when skill loading fails (filesystem, zip, database).
    class LoadError < Error; end

    # Raised when YAML frontmatter parsing fails.
    class ParseError < Error; end
  end
end
