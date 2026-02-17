# frozen_string_literal: true

# RubyLLM 1.12.0 Agent uses `delegate` but doesn't require ActiveSupport.
# Provide a minimal fallback for plain Ruby environments.
unless Module.method_defined?(:delegate)
  class Module
    def delegate(*methods, to:, prefix: nil, allow_nil: false, private: false, **_options)
      target_method = to.to_sym

      methods.each do |method_name|
        delegated_method = delegated_method_name(method_name, target_method, prefix)

        define_method(delegated_method) do |*args, **kwargs, &block|
          target = public_send(target_method)
          if target.nil?
            return nil if allow_nil

            raise NoMethodError,
              "#{self.class}##{delegated_method} delegated to ##{target_method}, but ##{target_method} is nil"
          end

          if kwargs.empty?
            target.public_send(method_name, *args, &block)
          else
            target.public_send(method_name, *args, **kwargs, &block)
          end
        end

        private delegated_method if binding.local_variable_get(:private)
      end
    end

    private

    def delegated_method_name(method_name, target_method, prefix)
      case prefix
      when true
        :"#{target_method}_#{method_name}"
      when String, Symbol
        :"#{prefix}_#{method_name}"
      else
        method_name
      end
    end
  end
end

require "ruby_llm"

require_relative "skills/version"
require_relative "skills/error"
require_relative "skills/parser"
require_relative "skills/validator"
require_relative "skills/skill"
require_relative "skills/loader"
require_relative "skills/filesystem_loader"
require_relative "skills/chat_extensions"
require_relative "skills/agent_extensions"

# Load Rails integration when Rails is available
require_relative "skills/railtie" if defined?(Rails::Railtie)

# Extend RubyLLM::Chat with skill methods
RubyLLM::Chat.include(RubyLLM::Skills::ChatExtensions)
RubyLLM::Agent.include(RubyLLM::Skills::AgentExtensions)

module RubyLLM
  module Skills
    class << self
      attr_accessor :default_path

      # Load skills from a filesystem directory.
      #
      # @param path [String] path to skills directory (defaults to default_path)
      # @return [FilesystemLoader] loader for the directory
      # @example
      #   RubyLLM::Skills.from_directory("app/skills")
      def from_directory(path = default_path)
        FilesystemLoader.new(path)
      end

      # Load a single skill from a directory.
      #
      # @param path [String] path to skill directory (containing SKILL.md)
      # @return [Skill] the loaded skill
      # @raise [LoadError] if SKILL.md not found
      # @example
      #   RubyLLM::Skills.load("app/skills/my-skill")
      def load(path)
        skill_md = File.join(path, "SKILL.md")
        raise LoadError, "SKILL.md not found in #{path}" unless File.exist?(skill_md)

        metadata = Parser.parse_file(skill_md)
        Skill.new(path: path, metadata: metadata)
      end

      # Load skills from database records.
      #
      # @param records [ActiveRecord::Relation, Array] collection of skill records
      # @return [DatabaseLoader] loader for the records
      # @example
      #   RubyLLM::Skills.from_database(Skill.where(active: true))
      def from_database(records)
        require_relative "skills/database_loader"
        DatabaseLoader.new(records)
      end

      # Create a composite loader from multiple sources.
      #
      # @param loaders [Array<Loader>] loaders to combine
      # @return [CompositeLoader] combined loader
      # @example
      #   RubyLLM::Skills.compose(
      #     RubyLLM::Skills.from_directory("app/skills"),
      #     RubyLLM::Skills.from_database(Skill.all)
      #   )
      def compose(*loaders)
        require_relative "skills/composite_loader"
        CompositeLoader.new(loaders)
      end
    end

    self.default_path = "app/skills"
  end
end
