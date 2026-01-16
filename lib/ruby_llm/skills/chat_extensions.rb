# frozen_string_literal: true

require_relative "skill_tool"

module RubyLlm
  module Skills
    # Extensions for RubyLLM::Chat to enable skill integration.
    #
    # @example With default path
    #   chat.with_skills
    #
    # @example With path
    #   chat.with_skills("app/skills")
    #
    # @example With multiple paths
    #   chat.with_skills("app/skills", "app/commands")
    #
    # @example With loader
    #   chat.with_skills(RubyLlm::Skills.from_directory("app/skills"))
    #
    # @example With array
    #   chat.with_skills(["app/skills", "app/commands"])
    #
    module ChatExtensions
      # Add skills to this chat.
      #
      # @param sources [String, Loader, Array] paths, loaders, or arrays of either
      # @return [self] for chaining
      def with_skills(*sources)
        sources = [RubyLlm::Skills.default_path] if sources.empty?
        sources = sources.flatten

        loader = if sources.length == 1
          to_loader(sources.first)
        else
          RubyLlm::Skills.compose(*sources.map { |s| to_loader(s) })
        end

        skill_tool = RubyLlm::Skills::SkillTool.new(loader)
        with_tool(skill_tool)
      end

      private

      def to_loader(source)
        source.is_a?(String) ? RubyLlm::Skills.from_directory(source) : source
      end
    end

    # Extensions for ActiveRecord models using acts_as_chat.
    #
    # @example
    #   chat = Chat.create!(model: "gpt-4")
    #   chat.with_skills
    #   chat.ask("Generate a PDF report")
    #
    module ActiveRecordExtensions
      # Add skills to this chat.
      #
      # @param sources [String, Loader, Array] paths, loaders, or arrays of either
      # @return [self] for chaining
      def with_skills(*sources)
        to_llm.with_skills(*sources)
        self
      end
    end
  end
end
