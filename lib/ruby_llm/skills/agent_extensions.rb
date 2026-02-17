# frozen_string_literal: true

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
      REQUIRED_AGENT_SINGLETON_METHODS = %i[apply_configuration runtime_context llm_chat_for].freeze

      module ClassMethods
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
          return [source] if database_collection_source?(source)
          return source.flat_map { |item| flatten_skill_sources(item) } if source.is_a?(Array)

          [source]
        end

        def loader_source?(source)
          source.respond_to?(:list) && source.respond_to?(:find)
        end

        def database_collection_source?(source)
          source.respond_to?(:to_a) && source.first&.respond_to?(:name) && source.first.respond_to?(:content)
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
        private

        def apply_configuration(chat_object, **kwargs)
          super
          input_values = kwargs[:input_values] || {}
          runtime = runtime_context(chat: chat_object, inputs: input_values)
          apply_skills(llm_chat_for(chat_object), runtime)
        end

        def apply_skills(llm_chat, runtime)
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
          llm_chat.with_skills(*normalized_sources, only: config[:only])
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
