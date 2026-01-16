# frozen_string_literal: true

module RubyLLM
  module Skills
    # Loads skills from a filesystem directory.
    #
    # Supports two formats:
    # 1. Directory skills: subdirectories containing SKILL.md files
    # 2. Single-file commands: .md files with frontmatter at the root level
    #
    # @example Directory skills
    #   app/skills/
    #   └── pdf-report/
    #       └── SKILL.md
    #
    # @example Single-file commands
    #   app/commands/
    #   └── write-poem.md
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

        directory_skills + single_file_skills
      end

      private

      # Load skills from subdirectories containing SKILL.md
      def directory_skills
        Dir.glob(File.join(@path, "*", "SKILL.md")).filter_map do |skill_md_path|
          load_directory_skill(skill_md_path)
        rescue ParseError => e
          log_warning("Failed to parse #{skill_md_path}: #{e.message}")
          nil
        end
      end

      # Load single-file .md commands from root level
      def single_file_skills
        Dir.glob(File.join(@path, "*.md")).filter_map do |md_path|
          load_single_file_skill(md_path)
        rescue ParseError => e
          log_warning("Failed to parse #{md_path}: #{e.message}")
          nil
        end
      end

      def load_directory_skill(skill_md_path)
        skill_dir = File.dirname(skill_md_path)
        metadata = Parser.parse_file(skill_md_path)

        Skill.new(path: skill_dir, metadata: metadata)
      end

      def load_single_file_skill(md_path)
        metadata = Parser.parse_file(md_path)

        # For single-file skills, the path is the file itself
        # They are virtual in that they have no resources
        Skill.new(path: md_path, metadata: metadata, virtual: true)
      end

      def log_warning(message)
        warn(message)
      end
    end
  end
end
