# frozen_string_literal: true

require_relative "source_detection"

module RubyLLM
  module Skills
    # Extensions for RubyLLM::Agent to enable declarative skill configuration.
    #
    # @example Static skills
    #   class SupportAgent < RubyLLM::Agent
    #     skills "app/skills", only: [:faq]
    #   end
    #
    # @example Dynamic skills
    #   class WorkspaceAgent < RubyLLM::Agent
    #     inputs :workspace
    #     skills { [workspace.skill_collection] }
    #   end
    #
    module AgentExtensions
      REQUIRED_AGENT_SINGLETON_METHODS = %i[apply_configuration runtime_context].freeze

      module ClassMethods
        include SourceDetection

        def self.extended(base)
          base.instance_variable_set(:@skill_sources, nil)
          base.instance_variable_set(:@skill_only, nil)
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@skill_sources, @skill_sources.is_a?(Proc) ? @skill_sources : @skill_sources&.dup)
          subclass.instance_variable_set(:@skill_only, @skill_only&.dup)
        end

        # Declare skill sources for this agent class.
        #
        # Called with no arguments, returns the current configuration.
        # Called with sources or a block, sets the configuration.
        #
        # @param sources [Array] skill sources
        # @param only [Array<Symbol, String>, nil] include only these skills
        # @return [Hash] current configuration when called as a getter
        def skills(*sources, only: nil, &block)
          if sources.empty? && only.nil? && !block_given?
            return {
              sources: @skill_sources.is_a?(Proc) ? @skill_sources : @skill_sources&.dup,
              only: @skill_only&.dup
            }
          end

          @skill_sources = block_given? ? block : normalize_skill_sources(sources)
          @skill_only = only&.dup
        end

        private

        def normalize_skill_sources(raw_sources)
          flatten_skill_sources(raw_sources).compact
        end

        def flatten_skill_sources(source)
          return [] if source.nil?
          return [source] if source.is_a?(String)
          return [source] if loader_source?(source)
          return source.empty? ? [] : [source] if database_collection_source?(source)
          return source.flat_map { |item| flatten_skill_sources(item) } if source.is_a?(Array)

          [source]
        end
      end

      module InstanceMethods
        # Add skills to this agent instance at runtime.
        #
        # @param sources [Array] skill sources
        # @param only [Array<Symbol, String>, nil] include only these skills
        # @return [self] for chaining
        def with_skills(*sources, only: nil)
          chat.with_skills(*sources, only: only)
          self
        end
      end

      module ConfigurationPatch
        # RubyLLM 2.0 passes either a RubyLLM::Chat or an acts_as_chat record.
        # Both respond to #with_skills (ChatExtensions / ActiveRecordExtensions),
        # so skills apply directly to whatever the agent configured.
        def apply_configuration(chat, input_values:, persist_instructions:)
          super
          runtime = runtime_context(chat: chat, inputs: input_values)
          apply_skills(chat, runtime)
        end

        private

        def apply_skills(chat, runtime)
          config = skills
          sources = config[:sources]
          return if sources.nil?

          resolved_sources = if sources.is_a?(Proc)
            runtime.instance_exec(&sources)
          else
            sources
          end

          normalized_sources = normalize_skill_sources(resolved_sources)
          return if normalized_sources.empty?

          validate_skill_sources!(normalized_sources)
          chat.with_skills(*normalized_sources, only: config[:only])
        end

        def validate_skill_sources!(sources)
          invalid_sources = sources.reject { |source| valid_skill_source?(source) }
          return if invalid_sources.empty?

          invalid_types = invalid_sources.map { |source| source.class.name || source.class.to_s }.uniq.join(", ")
          raise ArgumentError,
            "Invalid skill source(s): #{invalid_types}. Expected String path, Loader, or record collection."
        end

        def valid_skill_source?(source)
          source.is_a?(String) || loader_source?(source) || database_collection_source?(source)
        end
      end

      def self.included(base)
        missing_methods = REQUIRED_AGENT_SINGLETON_METHODS.reject do |method_name|
          base.singleton_class.private_method_defined?(method_name) || base.singleton_class.method_defined?(method_name)
        end

        if missing_methods.any?
          raise LoadError,
            "RubyLLM::Agent is missing required methods for ruby_llm-skills integration: #{missing_methods.join(", ")}"
        end

        base.extend(ClassMethods)
        base.include(InstanceMethods)
        base.singleton_class.prepend(ConfigurationPatch)
      end
    end
  end
end
