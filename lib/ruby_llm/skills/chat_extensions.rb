# frozen_string_literal: true

require_relative "skill_tool"

module RubyLLM
  module Skills
    # Extensions for RubyLLM::Chat to enable skill integration.
    #
    # @example Default (app/skills)
    #   chat.with_skills
    #
    # @example Custom path
    #   chat.with_skills("lib/skills")
    #
    # @example Multiple sources (auto-detected)
    #   chat.with_skills("app/skills", "app/commands", user.skills)
    #
    # @example Filter skills
    #   chat.with_skills(only: [:pdf_report])
    #
    module ChatExtensions
      # Add skills to this chat.
      #
      # @param sources [Array] skill sources - auto-detects type (directory, zip, collection)
      # @param only [Array<Symbol, String>, nil] include only these skills
      # @return [self] for chaining
      def with_skills(*sources, only: nil)
        sources = [RubyLLM::Skills.default_path] if sources.empty?
        loaders = sources.map { |s| to_loader(s) }

        loader = (loaders.length == 1) ? loaders.first : RubyLLM::Skills.compose(*loaders)
        loader = FilteredLoader.new(loader, only) if only

        skill_tool = RubyLLM::Skills::SkillTool.new(loader)
        with_tool(skill_tool)
      end

      private

      def to_loader(source)
        case source
        when String
          RubyLLM::Skills.from_directory(source)
        when ->(s) { database_collection_source?(s) }
          RubyLLM::Skills.from_database(source)
        when ->(s) { loader_source?(s) }
          source
        else
          raise ArgumentError,
            "Invalid skill source: #{source.class}. Expected String path, Loader, or record collection."
        end
      end

      def loader_source?(source)
        source.respond_to?(:list) && source.respond_to?(:find)
      end

      def database_collection_source?(source)
        source.respond_to?(:to_a) && source.first&.respond_to?(:name) && source.first.respond_to?(:content)
      end
    end

    # Simple wrapper that filters skills by name.
    class FilteredLoader
      def initialize(loader, only)
        @loader = loader
        @only = Array(only).map(&:to_s)
      end

      def list
        @loader.list.select { |s| @only.include?(s.name) }
      end

      def find(name)
        return nil unless @only.include?(name.to_s)
        @loader.find(name)
      end

      def get(name)
        raise NotFoundError, "Skill not found: #{name}" unless @only.include?(name.to_s)
        @loader.get(name)
      end

      def exists?(name)
        @only.include?(name.to_s) && @loader.exists?(name)
      end

      def reload!
        @loader.reload!
        self
      end
    end

    # Extensions for ActiveRecord models using acts_as_chat.
    module ActiveRecordExtensions
      def with_skills(*sources, only: nil)
        to_llm.with_skills(*sources, only: only)
        self
      end
    end
  end
end
