# frozen_string_literal: true

require_relative "skill_tool"

module RubyLlm
  module Skills
    # Extensions for RubyLLM::Chat to enable skill integration.
    #
    # @example
    #   chat = RubyLLM.chat
    #   chat.with_skills("app/skills")
    #   chat.ask("Generate a PDF report")
    #
    module ChatExtensions
      # Add skills from a directory to this chat.
      #
      # @param path [String] path to skills directory
      # @return [self] for chaining
      def with_skills(path = RubyLlm::Skills.default_path)
        loader = RubyLlm::Skills.from_directory(path)
        skill_tool = RubyLlm::Skills::SkillTool.new(loader)
        with_tool(skill_tool)
      end
    end

    # Extensions for ActiveRecord models using acts_as_chat.
    #
    # @example
    #   class Chat < ApplicationRecord
    #     acts_as_chat
    #   end
    #
    #   chat = Chat.create!(model: "gpt-4")
    #   chat.with_skills
    #   chat.ask("Generate a PDF report")
    #
    module ActiveRecordExtensions
      # Add skills from a directory to this chat.
      #
      # @param path [String] path to skills directory
      # @return [self] for chaining
      def with_skills(path = RubyLlm::Skills.default_path)
        to_llm.with_skills(path)
        self
      end
    end
  end
end
