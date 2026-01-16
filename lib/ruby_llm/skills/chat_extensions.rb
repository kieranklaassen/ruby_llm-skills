# frozen_string_literal: true

module RubyLlm
  module Skills
    # Extensions for RubyLLM::Chat to enable skill integration.
    #
    # These methods are added to RubyLLM::Chat when ruby_llm-skills is loaded,
    # providing a convenient API for adding skills to conversations.
    #
    # @example
    #   chat = RubyLlm.chat
    #   chat.with_skills("app/skills")
    #   chat.ask("Generate a PDF report")
    #
    module ChatExtensions
      # Add skills from a directory to this chat.
      #
      # @param path [String] path to skills directory
      # @return [self] for chaining
      # @example
      #   chat.with_skills("app/skills")
      def with_skills(path = RubyLlm::Skills.default_path)
        loader = RubyLlm::Skills.from_directory(path)
        skill_tool = RubyLlm::Skills::SkillTool.new(loader)
        with_tool(skill_tool)
      end

      # Add skills from a loader to this chat.
      #
      # @param loader [Loader] any skill loader
      # @return [self] for chaining
      # @example
      #   loader = RubyLlm::Skills.compose(
      #     RubyLlm::Skills.from_directory("app/skills"),
      #     RubyLlm::Skills.from_database(Skill.all)
      #   )
      #   chat.with_skill_loader(loader)
      def with_skill_loader(loader)
        skill_tool = RubyLlm::Skills::SkillTool.new(loader)
        with_tool(skill_tool)
      end
    end
  end
end

# Extend RubyLLM::Chat if available
if defined?(RubyLlm::Chat)
  RubyLlm::Chat.include(RubyLlm::Skills::ChatExtensions)
end
