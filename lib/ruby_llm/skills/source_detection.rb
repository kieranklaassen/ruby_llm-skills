# frozen_string_literal: true

module RubyLLM
  module Skills
    # Shared duck-typing predicates for classifying skill sources.
    # Used by both AgentExtensions and ChatExtensions.
    module SourceDetection
      private

      def loader_source?(source)
        source.respond_to?(:list) && source.respond_to?(:find)
      end

      def database_collection_source?(source)
        return false unless source.respond_to?(:to_a)

        # ActiveRecord relations/CollectionProxy: recognizable even when empty
        return true if source.respond_to?(:klass) && source.respond_to?(:where_values_hash)

        first = source.first
        first&.respond_to?(:name) && first.respond_to?(:content)
      end
    end
  end
end
