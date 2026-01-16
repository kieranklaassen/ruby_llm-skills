# frozen_string_literal: true

module RubyLlm
  module Skills
    # Represents a single skill with its metadata and content.
    #
    # Skills follow a progressive disclosure pattern:
    # - Level 1: Metadata (name, description) - loaded immediately
    # - Level 2: Content (SKILL.md body) - loaded lazily on demand
    # - Level 3: Resources (scripts, references, assets) - loaded lazily
    #
    # @example
    #   skill = Skill.new(
    #     path: "app/skills/pdf-report",
    #     metadata: { "name" => "pdf-report", "description" => "Generate PDFs" }
    #   )
    #   skill.name        # => "pdf-report" (immediate)
    #   skill.content     # => loads SKILL.md body (lazy)
    #   skill.scripts     # => lists script files (lazy)
    #
    class Skill
      attr_reader :path, :metadata

      # Initialize a skill from parsed metadata.
      #
      # @param path [String] path to skill directory or virtual identifier
      # @param metadata [Hash] parsed YAML frontmatter
      # @param content [String, nil] pre-loaded content (optional)
      def initialize(path:, metadata:, content: nil)
        @path = path.to_s
        @metadata = metadata || {}
        @content = content
      end

      # @return [String] skill name from frontmatter
      def name
        @metadata["name"]
      end

      # @return [String] skill description from frontmatter
      def description
        @metadata["description"]
      end

      # @return [String, nil] license from frontmatter
      def license
        @metadata["license"]
      end

      # @return [String, nil] compatibility info from frontmatter
      def compatibility
        @metadata["compatibility"]
      end

      # @return [Hash] custom metadata key-value pairs
      def custom_metadata
        @metadata["metadata"] || {}
      end

      # @return [Array<String>] list of allowed tools (experimental)
      def allowed_tools
        (@metadata["allowed-tools"] || "").split
      end

      # Get the full SKILL.md content (body without frontmatter).
      # Content is loaded lazily on first access.
      #
      # @return [String] skill instructions
      def content
        @content ||= load_content
      end

      # List script files in the scripts/ directory.
      # Loaded lazily on first access.
      #
      # @return [Array<String>] paths to script files
      def scripts
        @scripts ||= list_resources("scripts")
      end

      # List reference files in the references/ directory.
      # Loaded lazily on first access.
      #
      # @return [Array<String>] paths to reference files
      def references
        @references ||= list_resources("references")
      end

      # List asset files in the assets/ directory.
      # Loaded lazily on first access.
      #
      # @return [Array<String>] paths to asset files
      def assets
        @assets ||= list_resources("assets")
      end

      # Check if skill path is a filesystem path (vs database virtual path).
      #
      # @return [Boolean] true if path points to filesystem
      def filesystem?
        !virtual?
      end

      # Check if skill is a virtual/database skill.
      #
      # @return [Boolean] true if path is a virtual identifier
      def virtual?
        @path.start_with?("database:")
      end

      # Path to the SKILL.md file.
      #
      # @return [String, nil] path to SKILL.md or nil for virtual skills
      def skill_md_path
        return nil if virtual?

        File.join(@path, "SKILL.md")
      end

      # Validate the skill structure.
      #
      # @return [Boolean] true if skill is valid
      def valid?
        errors.empty?
      end

      # Get validation errors.
      #
      # @return [Array<String>] list of error messages
      def errors
        @errors ||= Validator.validate(self)
      end

      # Clear cached content and resources (useful for testing).
      def reload!
        @content = nil
        @scripts = nil
        @references = nil
        @assets = nil
        @errors = nil
        self
      end

      # @return [String] inspection string
      def inspect
        "#<#{self.class.name} name=#{name.inspect} path=#{path.inspect}>"
      end

      private

      def load_content
        return @metadata["__content__"] if @metadata["__content__"]
        return "" if virtual?

        md_path = skill_md_path
        return "" unless md_path && File.exist?(md_path)

        Parser.extract_body(File.read(md_path))
      end

      def list_resources(subdir)
        return [] if virtual?

        resource_path = File.join(@path, subdir)
        return [] unless File.directory?(resource_path)

        Dir.glob(File.join(resource_path, "**", "*"))
          .select { |f| File.file?(f) }
          .reject { |f| File.basename(f) == ".keep" }
          .sort
      end
    end
  end
end
