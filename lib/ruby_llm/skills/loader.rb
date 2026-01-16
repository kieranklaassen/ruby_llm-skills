# frozen_string_literal: true

module RubyLLM
  module Skills
    # Base class for skill loaders.
    #
    # Loaders are responsible for discovering and loading skills from various sources:
    # - FilesystemLoader: loads from directory structures
    # - ZipLoader: loads from .zip archives
    # - DatabaseLoader: loads from ActiveRecord models
    #
    # @example
    #   loader = FilesystemLoader.new("app/skills")
    #   loader.list         # => [skill1, skill2, ...]
    #   loader.find("name") # => Skill or nil
    #   loader.get("name")  # => Skill or raises NotFoundError
    #
    class Loader
      # List all skills from this source.
      #
      # @return [Array<Skill>] collection of skills
      def list
        raise NotImplementedError, "#{self.class}#list must be implemented"
      end

      # Find a skill by name.
      #
      # @param name [String] skill name
      # @return [Skill, nil] skill or nil if not found
      def find(name)
        list.find { |skill| skill.name == name }
      end

      # Get a skill by name, raising if not found.
      #
      # @param name [String] skill name
      # @return [Skill] the found skill
      # @raise [NotFoundError] if skill not found
      def get(name)
        skill = find(name)
        raise NotFoundError, "Skill not found: #{name}" unless skill

        skill
      end

      # Check if a skill exists.
      #
      # @param name [String] skill name
      # @return [Boolean] true if skill exists
      def exists?(name)
        !find(name).nil?
      end

      # Reload all skills, clearing any cache.
      #
      # @return [self]
      def reload!
        @skills = nil
        self
      end

      protected

      # Cache skills from #load_all for performance.
      def skills
        @skills ||= load_all
      end

      # Subclasses must implement this to load all skills.
      #
      # @return [Array<Skill>] all skills from source
      def load_all
        raise NotImplementedError, "#{self.class}#load_all must be implemented"
      end
    end
  end
end
