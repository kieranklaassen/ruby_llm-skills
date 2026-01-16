# frozen_string_literal: true

require_relative "skills/version"
require_relative "skills/error"
require_relative "skills/parser"
require_relative "skills/validator"
require_relative "skills/skill"
require_relative "skills/loader"
require_relative "skills/filesystem_loader"

# Load Rails integration when Rails is available
require_relative "skills/railtie" if defined?(Rails::Railtie)

module RubyLlm
  module Skills
    class << self
      attr_accessor :default_path, :logger

      # Load skills from a filesystem directory.
      #
      # @param path [String] path to skills directory (defaults to default_path)
      # @return [FilesystemLoader] loader for the directory
      # @example
      #   RubyLlm::Skills.from_directory("app/skills")
      def from_directory(path = default_path)
        FilesystemLoader.new(path)
      end

      # Load a single skill from a directory.
      #
      # @param path [String] path to skill directory (containing SKILL.md)
      # @return [Skill] the loaded skill
      # @raise [LoadError] if SKILL.md not found
      # @example
      #   RubyLlm::Skills.load("app/skills/my-skill")
      def load(path)
        skill_md = File.join(path, "SKILL.md")
        raise LoadError, "SKILL.md not found in #{path}" unless File.exist?(skill_md)

        metadata = Parser.parse_file(skill_md)
        Skill.new(path: path, metadata: metadata)
      end

      # Load skills from a zip archive.
      #
      # @param path [String] path to .zip file
      # @return [ZipLoader] loader for the archive
      # @raise [LoadError] if rubyzip not available
      # @example
      #   RubyLlm::Skills.from_zip("skills.zip")
      def from_zip(path)
        require_relative "skills/zip_loader"
        ZipLoader.new(path)
      rescue ::LoadError
        raise LoadError, "rubyzip gem required for zip support. Add 'gem \"rubyzip\"' to your Gemfile."
      end

      # Load skills from database records.
      #
      # @param records [ActiveRecord::Relation, Array] collection of skill records
      # @return [DatabaseLoader] loader for the records
      # @example
      #   RubyLlm::Skills.from_database(Skill.where(active: true))
      def from_database(records)
        require_relative "skills/database_loader"
        DatabaseLoader.new(records)
      end

      # Create a composite loader from multiple sources.
      #
      # @param loaders [Array<Loader>] loaders to combine
      # @return [CompositeLoader] combined loader
      # @example
      #   RubyLlm::Skills.compose(
      #     RubyLlm::Skills.from_directory("app/skills"),
      #     RubyLlm::Skills.from_database(Skill.all)
      #   )
      def compose(*loaders)
        require_relative "skills/composite_loader"
        CompositeLoader.new(loaders)
      end
    end

    self.default_path = "app/skills"
  end
end
