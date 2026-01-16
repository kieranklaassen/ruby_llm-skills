# frozen_string_literal: true

module RubyLLM
  module Skills
    # Combines multiple loaders into a single source.
    #
    # Skills are searched in order, with earlier loaders taking precedence.
    # This allows layering skills from multiple sources (filesystem, database, etc).
    #
    # @example
    #   composite = CompositeLoader.new([
    #     FilesystemLoader.new("app/skills"),
    #     DatabaseLoader.new(Skill.all)
    #   ])
    #   composite.list  # => skills from all loaders
    #
    class CompositeLoader < Loader
      attr_reader :loaders

      # Initialize with an array of loaders.
      #
      # @param loaders [Array<Loader>] loaders to combine
      def initialize(loaders)
        super()
        @loaders = loaders
      end

      # List all skills from all loaders.
      # Skills are deduplicated by name, with earlier loaders taking precedence.
      #
      # @return [Array<Skill>] combined list of skills
      def list
        skills
      end

      # Reload all loaders.
      #
      # @return [self]
      def reload!
        @loaders.each(&:reload!)
        super
      end

      protected

      def load_all
        seen = {}
        @loaders.flat_map(&:list).each_with_object([]) do |skill, result|
          next if seen[skill.name]

          seen[skill.name] = true
          result << skill
        end
      end
    end
  end
end
