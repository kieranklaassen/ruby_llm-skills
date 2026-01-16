# frozen_string_literal: true

require "yaml"

module RubyLlm
  module Skills
    # Parses SKILL.md files with YAML frontmatter.
    #
    # A valid SKILL.md has the format:
    #   ---
    #   name: skill-name
    #   description: What the skill does
    #   ---
    #   # Skill content here
    #
    class Parser
      # Regex to match YAML frontmatter between --- delimiters
      FRONTMATTER_REGEX = /\A---\n(.*?)\n---\n?(.*)/m

      class << self
        # Parse a SKILL.md file and extract frontmatter metadata.
        #
        # @param path [String, Pathname] path to SKILL.md file
        # @return [Hash] parsed frontmatter as hash
        # @raise [ParseError] if frontmatter is missing or invalid
        def parse_file(path)
          content = File.read(path)
          parse_string(content)
        rescue Errno::ENOENT
          raise ParseError, "File not found: #{path}"
        rescue Errno::EACCES
          raise ParseError, "Permission denied: #{path}"
        end

        # Parse SKILL.md content string and extract frontmatter.
        #
        # @param content [String] full SKILL.md content
        # @return [Hash] parsed frontmatter as hash
        # @raise [ParseError] if frontmatter is missing or invalid
        def parse_string(content)
          match = content.match(FRONTMATTER_REGEX)

          unless match
            raise ParseError, "Missing YAML frontmatter (must start with ---)"
          end

          yaml_content = match[1]
          parse_yaml(yaml_content)
        end

        # Extract the body content (everything after frontmatter).
        #
        # @param content [String] full SKILL.md content
        # @return [String] body content without frontmatter
        def extract_body(content)
          match = content.match(FRONTMATTER_REGEX)
          return "" unless match

          match[2].to_s.strip
        end

        private

        def parse_yaml(yaml_content)
          # Use safe_load with permitted classes for security
          YAML.safe_load(
            yaml_content,
            permitted_classes: [Symbol],
            permitted_symbols: [],
            aliases: false
          ) || {}
        rescue Psych::SyntaxError => e
          raise ParseError, "Invalid YAML frontmatter: #{e.message}"
        rescue Psych::DisallowedClass => e
          raise ParseError, "Disallowed class in YAML: #{e.message}"
        end
      end
    end
  end
end
