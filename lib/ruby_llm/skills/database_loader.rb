# frozen_string_literal: true

module RubyLlm
  module Skills
    # Loads skills from database records using duck-typing.
    #
    # Records must respond to either:
    # - Text storage: #name, #description, #content
    # - Binary storage: #name, #description, #data (zip blob)
    #
    # Optional methods: #license, #compatibility, #metadata
    #
    # @example With text content
    #   class SkillRecord
    #     attr_accessor :name, :description, :content
    #   end
    #   loader = DatabaseLoader.new(SkillRecord.all)
    #
    # @example With ActiveRecord
    #   loader = DatabaseLoader.new(Skill.where(active: true))
    #
    class DatabaseLoader < Loader
      attr_reader :records

      # Initialize with a collection of records.
      #
      # @param records [Enumerable] collection responding to #each
      def initialize(records)
        super()
        @records = records
      end

      # List all skills from the records.
      #
      # @return [Array<Skill>] skills from records
      def list
        skills
      end

      # Reload skills by re-iterating records.
      # Also reloads the records if they respond to #reload.
      #
      # @return [self]
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
        if binary_storage?(record)
          load_from_binary(record)
        else
          load_from_text(record)
        end
      end

      def binary_storage?(record)
        record.respond_to?(:data) && record.data.present?
      end

      def load_from_text(record)
        validate_text_record!(record)

        metadata = build_metadata(record)
        metadata["__content__"] = record.content.to_s

        Skill.new(
          path: "database:#{record_id(record)}",
          metadata: metadata
        )
      end

      def load_from_binary(record)
        # Extract skill from zip data
        require "zip"
        require "stringio"

        io = StringIO.new(record.data)
        Zip::File.open_buffer(io) do |zip|
          skill_md_entry = zip.find_entry("SKILL.md")
          raise LoadError, "SKILL.md not found in binary data" unless skill_md_entry

          content = skill_md_entry.get_input_stream.read
          metadata = Parser.parse_string(content)
          body = Parser.extract_body(content)

          # Override name/description from record if present
          metadata["name"] = record.name if record.respond_to?(:name) && record.name
          metadata["description"] = record.description if record.respond_to?(:description) && record.description
          metadata["__content__"] = body

          Skill.new(
            path: "database:#{record_id(record)}",
            metadata: metadata
          )
        end
      rescue ::LoadError
        raise LoadError, "rubyzip gem required for binary storage. Add 'gem \"rubyzip\"' to your Gemfile."
      end

      def validate_text_record!(record)
        raise InvalidSkillError, "Record must respond to #name" unless record.respond_to?(:name)
        raise InvalidSkillError, "Record must respond to #description" unless record.respond_to?(:description)
        raise InvalidSkillError, "Record must respond to #content" unless record.respond_to?(:content)
      end

      def build_metadata(record)
        metadata = {
          "name" => record.name.to_s,
          "description" => record.description.to_s
        }

        metadata["license"] = record.license.to_s if record.respond_to?(:license) && record.license
        metadata["compatibility"] = record.compatibility.to_s if record.respond_to?(:compatibility) && record.compatibility

        if record.respond_to?(:skill_metadata) && record.skill_metadata.is_a?(Hash)
          metadata["metadata"] = record.skill_metadata
        end

        metadata
      end

      def record_id(record)
        if record.respond_to?(:id)
          record.id
        elsif record.respond_to?(:name)
          record.name
        else
          record.object_id
        end
      end
    end
  end
end
