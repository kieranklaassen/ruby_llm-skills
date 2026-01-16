# frozen_string_literal: true

require "test_helper"
require "ruby_llm/skills/database_loader"

class RubyLLM::Skills::TestDatabaseLoader < Minitest::Test
  def setup
    @records = [
      MockRecord.new(id: 1, name: "db-skill-one", description: "First database skill", content: "# Skill One\n\nContent here"),
      MockRecord.new(id: 2, name: "db-skill-two", description: "Second database skill", content: "# Skill Two")
    ]
    @loader = RubyLLM::Skills::DatabaseLoader.new(@records)
  end

  def test_initialize_with_records
    loader = RubyLLM::Skills::DatabaseLoader.new(@records)
    assert_equal @records, loader.records
  end

  def test_list_returns_skills_array
    skills = @loader.list
    assert_instance_of Array, skills
    assert skills.all? { |s| s.is_a?(RubyLLM::Skills::Skill) }
  end

  def test_list_creates_skill_for_each_record
    skills = @loader.list
    assert_equal 2, skills.length
  end

  def test_find_returns_skill_by_name
    skill = @loader.find("db-skill-one")
    assert_instance_of RubyLLM::Skills::Skill, skill
    assert_equal "db-skill-one", skill.name
  end

  def test_find_returns_nil_for_unknown_name
    skill = @loader.find("nonexistent-skill")
    assert_nil skill
  end

  def test_loaded_skill_has_correct_metadata
    skill = @loader.find("db-skill-one")

    assert_equal "db-skill-one", skill.name
    assert_equal "First database skill", skill.description
  end

  def test_loaded_skill_content_is_available
    skill = @loader.find("db-skill-one")
    content = skill.content

    assert_includes content, "# Skill One"
    assert_includes content, "Content here"
  end

  def test_skill_path_indicates_database_source
    skill = @loader.find("db-skill-one")
    assert skill.path.start_with?("database:")
    assert_includes skill.path, "1"
  end

  def test_skill_is_virtual
    skill = @loader.find("db-skill-one")
    assert skill.virtual?
  end

  def test_skills_are_cached
    first_list = @loader.list
    second_list = @loader.list
    assert_same first_list, second_list
  end

  def test_reload_clears_cache
    initial_skills = @loader.list
    result = @loader.reload!

    assert_same @loader, result
    refute_same initial_skills, @loader.list
  end

  def test_reload_calls_reload_on_records_if_available
    reloadable = MockReloadableRecords.new(@records)
    loader = RubyLLM::Skills::DatabaseLoader.new(reloadable)

    loader.reload!
    assert reloadable.reloaded?
  end

  def test_optional_license_is_loaded
    record = MockRecord.new(
      id: 3,
      name: "licensed-skill",
      description: "A skill with license",
      content: "# Content",
      license: "MIT"
    )
    loader = RubyLLM::Skills::DatabaseLoader.new([record])
    skill = loader.find("licensed-skill")

    assert_equal "MIT", skill.license
  end

  def test_optional_compatibility_is_loaded
    record = MockRecord.new(
      id: 4,
      name: "compatible-skill",
      description: "A skill with compatibility",
      content: "# Content",
      compatibility: "RubyLLM 1.0+"
    )
    loader = RubyLLM::Skills::DatabaseLoader.new([record])
    skill = loader.find("compatible-skill")

    assert_equal "RubyLLM 1.0+", skill.compatibility
  end

  def test_optional_metadata_is_loaded
    record = MockRecord.new(
      id: 5,
      name: "meta-skill",
      description: "A skill with metadata",
      content: "# Content",
      skill_metadata: {"author" => "test", "version" => "1.0"}
    )
    loader = RubyLLM::Skills::DatabaseLoader.new([record])
    skill = loader.find("meta-skill")

    assert_equal({"author" => "test", "version" => "1.0"}, skill.custom_metadata)
  end

  def test_handles_empty_records
    loader = RubyLLM::Skills::DatabaseLoader.new([])
    assert_equal [], loader.list
  end

  def test_from_database_module_method
    loader = RubyLLM::Skills.from_database(@records)
    assert_instance_of RubyLLM::Skills::DatabaseLoader, loader
  end

  def test_record_without_id_uses_name
    record = MockRecordWithoutId.new(
      name: "no-id-skill",
      description: "Skill without id",
      content: "# Content"
    )
    loader = RubyLLM::Skills::DatabaseLoader.new([record])
    skill = loader.find("no-id-skill")

    assert_includes skill.path, "no-id-skill"
  end

  # Mock classes for testing
  class MockRecord
    attr_accessor :id, :name, :description, :content, :license, :compatibility, :skill_metadata

    def initialize(attrs = {})
      attrs.each { |k, v| send("#{k}=", v) }
    end
  end

  class MockRecordWithoutId
    attr_accessor :name, :description, :content

    def initialize(attrs = {})
      attrs.each { |k, v| send("#{k}=", v) }
    end
  end

  class MockReloadableRecords
    def initialize(records)
      @records = records
      @reloaded = false
    end

    def each(&block)
      @records.each(&block)
    end

    def reload
      @reloaded = true
      self
    end

    def reloaded?
      @reloaded
    end
  end
end
