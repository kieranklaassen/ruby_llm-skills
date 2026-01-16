# frozen_string_literal: true

module RubyLlm
  module Skills
    # Loads skills from a filesystem directory.
    #
    # Scans a directory for subdirectories containing SKILL.md files.
    # Each subdirectory is treated as a skill if it contains a valid SKILL.md.
    #
    # @example
    #   loader = FilesystemLoader.new("app/skills")
    #   loader.list # => [Skill, Skill, ...]
    #
    class FilesystemLoader < Loader
      attr_reader :path

      # Initialize with a directory path.
      #
      # @param path [String, Pathname] path to skills directory
      def initialize(path)
        super()
        @path = path.to_s
      end

      # List all skills from the directory.
      #
      # @return [Array<Skill>] skills found in directory
      def list
        skills
      end

      protected

      def load_all
        return [] unless File.directory?(@path)

        Dir.glob(File.join(@path, "*", "SKILL.md")).filter_map do |skill_md_path|
          load_skill(skill_md_path)
        rescue ParseError => e
          warn "Warning: Failed to parse #{skill_md_path}: #{e.message}" if RubyLlm::Skills.logger
          nil
        end
      end

      private

      def load_skill(skill_md_path)
        skill_dir = File.dirname(skill_md_path)
        metadata = Parser.parse_file(skill_md_path)

        Skill.new(path: skill_dir, metadata: metadata)
      end
    end
  end
end
