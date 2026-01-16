# frozen_string_literal: true

require "zip"

module RubyLlm
  module Skills
    # Loads skills from a ZIP archive.
    #
    # The archive should contain skill directories at the root level,
    # each with a SKILL.md file.
    #
    # Structure:
    #   archive.zip
    #   ├── skill-one/
    #   │   ├── SKILL.md
    #   │   └── scripts/
    #   └── skill-two/
    #       └── SKILL.md
    #
    # @example
    #   loader = ZipLoader.new("skills.zip")
    #   loader.list  # => [Skill, Skill, ...]
    #
    class ZipLoader < Loader
      attr_reader :path

      # Initialize with path to zip file.
      #
      # @param path [String] path to .zip archive
      # @raise [LoadError] if file doesn't exist
      def initialize(path)
        super()
        @path = path.to_s
        raise LoadError, "Zip file not found: #{@path}" unless File.exist?(@path)
      end

      # List all skills from the archive.
      #
      # @return [Array<Skill>] skills found in archive
      def list
        skills
      end

      # Read content of a file within a skill's directory.
      #
      # @param skill_name [String] name of the skill
      # @param relative_path [String] path relative to skill directory
      # @return [String, nil] file content or nil if not found
      def read_file(skill_name, relative_path)
        entry_path = "#{skill_name}/#{relative_path}"
        read_zip_entry(entry_path)
      end

      protected

      def load_all
        loaded_skills = []

        Zip::File.open(@path) do |zip|
          skill_dirs = find_skill_directories(zip)

          skill_dirs.each do |skill_dir|
            skill = load_skill_from_zip(zip, skill_dir)
            loaded_skills << skill if skill
          end
        end

        loaded_skills
      rescue Zip::Error => e
        raise LoadError, "Failed to read zip archive: #{e.message}"
      end

      private

      def find_skill_directories(zip)
        zip.entries
          .select { |e| e.name.end_with?("/SKILL.md") }
          .map { |e| File.dirname(e.name) }
          .reject { |d| d.include?("/") } # Only top-level skills
      end

      def load_skill_from_zip(zip, skill_dir)
        skill_md_path = "#{skill_dir}/SKILL.md"
        entry = zip.find_entry(skill_md_path)
        return nil unless entry

        content = entry.get_input_stream.read
        metadata = Parser.parse_string(content)
        body = Parser.extract_body(content)

        # Store content in metadata for virtual skill
        metadata["__content__"] = body

        # Store resource lists
        metadata["__scripts__"] = list_resources(zip, skill_dir, "scripts")
        metadata["__references__"] = list_resources(zip, skill_dir, "references")
        metadata["__assets__"] = list_resources(zip, skill_dir, "assets")

        Skill.new(
          path: "zip:#{@path}:#{skill_dir}",
          metadata: metadata
        )
      rescue ParseError => e
        warn "Warning: Failed to parse #{skill_md_path}: #{e.message}" if RubyLlm::Skills.logger
        nil
      end

      def list_resources(zip, skill_dir, subdir)
        prefix = "#{skill_dir}/#{subdir}/"
        zip.entries
          .select { |e| e.name.start_with?(prefix) && !e.directory? }
          .map { |e| e.name.sub(prefix, "") }
          .reject { |f| f == ".keep" }
          .sort
      end

      def read_zip_entry(entry_path)
        Zip::File.open(@path) do |zip|
          entry = zip.find_entry(entry_path)
          return nil unless entry

          entry.get_input_stream.read
        end
      rescue Zip::Error
        nil
      end
    end
  end
end
