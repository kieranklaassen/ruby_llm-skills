# frozen_string_literal: true

module RubyLLM
  module Skills
    # Validates skill structure according to the Agent Skills specification.
    #
    # Validation rules based on agentskills.io specification:
    # - name: required, max 64 chars, lowercase + hyphens only, no leading/trailing hyphens
    # - description: required, max 1024 chars
    # - license: optional, max 128 chars
    # - compatibility: optional, max 500 chars
    #
    # @example
    #   errors = Validator.validate(skill)
    #   puts errors # => [] if valid, or list of error messages
    #
    class Validator
      NAME_MAX_LENGTH = 64
      DESCRIPTION_MAX_LENGTH = 1024
      LICENSE_MAX_LENGTH = 128
      COMPATIBILITY_MAX_LENGTH = 500
      NAME_PATTERN = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

      class << self
        # Validate a skill and return all errors.
        #
        # @param skill [Skill] skill to validate
        # @return [Array<String>] list of error messages (empty if valid)
        def validate(skill)
          errors = []
          validate_name(skill, errors)
          validate_description(skill, errors)
          validate_license(skill, errors)
          validate_compatibility(skill, errors)
          validate_path_name_match(skill, errors)
          errors
        end

        # Check if a skill is valid.
        #
        # @param skill [Skill] skill to validate
        # @return [Boolean] true if skill passes validation
        def valid?(skill)
          validate(skill).empty?
        end

        private

        def validate_name(skill, errors)
          name = skill.name

          if name.nil? || name.empty?
            errors << "name is required"
            return
          end

          if name.length > NAME_MAX_LENGTH
            errors << "name exceeds maximum length of #{NAME_MAX_LENGTH} characters"
          end

          unless name.match?(NAME_PATTERN)
            errors << "name must be lowercase letters, numbers, and single hyphens (no leading/trailing hyphens)"
          end
        end

        def validate_description(skill, errors)
          description = skill.description

          if description.nil? || description.empty?
            errors << "description is required"
            return
          end

          if description.length > DESCRIPTION_MAX_LENGTH
            errors << "description exceeds maximum length of #{DESCRIPTION_MAX_LENGTH} characters"
          end
        end

        def validate_license(skill, errors)
          license = skill.license
          return if license.nil? || license.empty?

          if license.length > LICENSE_MAX_LENGTH
            errors << "license exceeds maximum length of #{LICENSE_MAX_LENGTH} characters"
          end
        end

        def validate_compatibility(skill, errors)
          compatibility = skill.compatibility
          return if compatibility.nil? || compatibility.empty?

          if compatibility.length > COMPATIBILITY_MAX_LENGTH
            errors << "compatibility exceeds maximum length of #{COMPATIBILITY_MAX_LENGTH} characters"
          end
        end

        def validate_path_name_match(skill, errors)
          return if skill.virtual?

          dir_name = File.basename(skill.path)
          return if skill.name == dir_name

          errors << "name '#{skill.name}' does not match directory name '#{dir_name}'"
        end
      end
    end
  end
end
