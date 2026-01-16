# frozen_string_literal: true

require "ruby_llm"

module RubyLlm
  module Skills
    # A RubyLLM Tool that enables progressive skill loading.
    #
    # This tool is the key integration point for LLM skill discovery.
    # It embeds skill metadata (name + description) in its description,
    # allowing the LLM to discover available skills. When invoked,
    # it returns the full skill content.
    #
    # Progressive Disclosure Pattern:
    # 1. Skill metadata is always visible in the tool description (~100 tokens/skill)
    # 2. Full skill content is loaded on-demand when the tool is called (~5k tokens)
    # 3. Resources (scripts, references) can be loaded separately as needed
    #
    # @example Basic usage
    #   loader = RubyLlm::Skills.from_directory("app/skills")
    #   skill_tool = RubyLlm::Skills::SkillTool.new(loader)
    #
    #   chat.with_tools(skill_tool)
    #   chat.ask("Help me generate a PDF report")
    #   # LLM sees available skills, calls skill_tool with name="pdf-report"
    #   # Tool returns full SKILL.md content for LLM to follow
    #
    class SkillTool < RubyLLM::Tool
      description "Load a skill to get specialized instructions for a task."
      param :skill_name, type: "string",
        desc: "The name of the skill to load (from the available skills list)"

      attr_reader :loader

      # Initialize with a skill loader.
      #
      # @param loader [Loader] any loader (FilesystemLoader, ZipLoader, etc.)
      def initialize(loader)
        @loader = loader
      end

      # Tool name for RubyLLM.
      #
      # @return [String] "skill"
      def name
        "skill"
      end

      # Dynamic description including available skills.
      #
      # @return [String] tool description with embedded skill metadata
      def description
        base_description = self.class.description
        skills_xml = build_skills_xml
        <<~DESC.strip
          #{base_description}

          Use this tool when the user's request matches one of the available skills.
          The tool returns the full skill instructions that you should follow.

          #{skills_xml}
        DESC
      end

      # Execute the tool to load a skill's content.
      #
      # @param skill_name [String] name of skill to load
      # @return [String] skill content or error message
      def execute(skill_name:)
        skill = @loader.find(skill_name)

        unless skill
          available = @loader.list.map(&:name).join(", ")
          return "Skill '#{skill_name}' not found. Available skills: #{available}"
        end

        build_skill_response(skill)
      end

      # Convert to RubyLLM Tool-compatible format.
      #
      # @return [Hash] tool definition for RubyLLM
      def to_tool_definition
        {
          name: name,
          description: description,
          parameters: params_schema
        }
      end

      private

      def build_skills_xml
        skills = @loader.list

        return "<available_skills>\nNo skills available.\n</available_skills>" if skills.empty?

        xml_parts = ["<available_skills>"]

        skills.each do |skill|
          xml_parts << "  <skill>"
          xml_parts << "    <name>#{escape_xml(skill.name)}</name>"
          xml_parts << "    <description>#{escape_xml(skill.description)}</description>"
          xml_parts << "  </skill>"
        end

        xml_parts << "</available_skills>"
        xml_parts.join("\n")
      end

      def build_skill_response(skill)
        parts = []
        parts << "# Skill: #{skill.name}"
        parts << ""
        parts << skill.content
        parts << ""

        # Include resource information if available
        if skill.scripts.any?
          parts << "## Available Scripts"
          skill.scripts.each { |s| parts << "- #{File.basename(s)}" }
          parts << ""
        end

        if skill.references.any?
          parts << "## Available References"
          skill.references.each { |r| parts << "- #{File.basename(r)}" }
          parts << ""
        end

        if skill.assets.any?
          parts << "## Available Assets"
          skill.assets.each { |a| parts << "- #{File.basename(a)}" }
          parts << ""
        end

        parts.join("\n").strip
      end

      def escape_xml(text)
        return "" if text.nil?

        text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
          .gsub("'", "&apos;")
      end
    end
  end
end
