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
            return {sources: @skill_sources, only: @skill_only}
          end

          @skill_sources = block_given? ? block : sources
          @skill_only = only
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

          llm_chat.with_skills(*Array(resolved_sources), only: config[:only])
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
        base.singleton_class.prepend(ConfigurationPatch)
      end
    end
  end
end
