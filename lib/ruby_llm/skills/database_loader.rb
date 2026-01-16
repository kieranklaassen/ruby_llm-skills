# frozen_string_literal: true

module RubyLlm
  module Skills
    # Loads skills from database records.
    #
    # Records must respond to: #name, #description, #content
    # Optional: #license, #compatibility, #skill_metadata
    #
    # @example
    #   loader = DatabaseLoader.new(Skill.where(user: current_user))
    #
    class DatabaseLoader < Loader
      attr_reader :records

      def initialize(records)
        super()
        @records = records
      end

      def list
        skills
      end

      def reload!
        @records.reload if @records.respond_to?(:reload)
        super
      end

      protected

      def load_all
        @records.filter_map do |record|
          load_skill_from_record(record)
        rescue => e
          warn "Failed to load skill from record: #{e.message}"
          nil
        end
      end

      private

      def load_skill_from_record(record)
        validate_record!(record)

        metadata = {
          "name" => record.name.to_s,
          "description" => record.description.to_s,
          "__content__" => record.content.to_s
        }

        metadata["license"] = record.license.to_s if record.respond_to?(:license) && record.license
        metadata["compatibility"] = record.compatibility.to_s if record.respond_to?(:compatibility) && record.compatibility

        if record.respond_to?(:skill_metadata) && record.skill_metadata.is_a?(Hash)
          metadata["metadata"] = record.skill_metadata
        end

        Skill.new(
          path: "database:#{record_id(record)}",
          metadata: metadata
        )
      end

      def validate_record!(record)
        raise InvalidSkillError, "Record must respond to #name" unless record.respond_to?(:name)
        raise InvalidSkillError, "Record must respond to #description" unless record.respond_to?(:description)
        raise InvalidSkillError, "Record must respond to #content" unless record.respond_to?(:content)
      end

      def record_id(record)
        record.respond_to?(:id) ? record.id : record.name
      end
    end
  end
end
