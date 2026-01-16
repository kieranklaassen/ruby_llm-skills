# frozen_string_literal: true

require "test_helper"
require "ruby_llm/skills/zip_loader"
require "tmpdir"

class RubyLlm::Skills::TestZipLoader < Minitest::Test
  def setup
    @zip_path = create_test_zip
    @loader = RubyLlm::Skills::ZipLoader.new(@zip_path)
  end

  def teardown
    File.delete(@zip_path) if @zip_path && File.exist?(@zip_path)
  end

  def test_initialize_with_path
    assert_equal @zip_path, @loader.path
  end

  def test_initialize_raises_on_missing_file
    error = assert_raises(RubyLlm::Skills::LoadError) do
      RubyLlm::Skills::ZipLoader.new("/nonexistent/file.zip")
    end
    assert_match(/Zip file not found/, error.message)
  end

  def test_list_returns_skills_array
    skills = @loader.list
    assert_instance_of Array, skills
    assert skills.all? { |s| s.is_a?(RubyLlm::Skills::Skill) }
  end

  def test_list_finds_skills_in_archive
    skills = @loader.list
    skill_names = skills.map(&:name)

    assert_includes skill_names, "zip-skill-one"
    assert_includes skill_names, "zip-skill-two"
  end

  def test_find_returns_skill_by_name
    skill = @loader.find("zip-skill-one")
    assert_instance_of RubyLlm::Skills::Skill, skill
    assert_equal "zip-skill-one", skill.name
  end

  def test_find_returns_nil_for_unknown_name
    skill = @loader.find("nonexistent-skill")
    assert_nil skill
  end

  def test_loaded_skill_has_correct_metadata
    skill = @loader.find("zip-skill-one")

    assert_equal "zip-skill-one", skill.name
    assert_equal "First zip skill", skill.description
  end

  def test_loaded_skill_content_is_available
    skill = @loader.find("zip-skill-one")
    content = skill.content

    assert_includes content, "# Zip Skill One"
    assert_includes content, "Instructions for the first skill"
  end

  def test_skill_path_indicates_zip_source
    skill = @loader.find("zip-skill-one")
    assert skill.path.start_with?("zip:")
    assert_includes skill.path, @zip_path
  end

  def test_skill_is_virtual
    skill = @loader.find("zip-skill-one")
    # Zip skills have paths like "zip:/path/to/file.zip:skill-name"
    # They're not database: prefixed, so not virtual in that sense
    refute skill.virtual?
  end

  def test_read_file_returns_file_content
    content = @loader.read_file("zip-skill-one", "scripts/helper.rb")
    assert_includes content, "helper code"
  end

  def test_read_file_returns_nil_for_missing_file
    content = @loader.read_file("zip-skill-one", "nonexistent.txt")
    assert_nil content
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

  def test_list_returns_empty_for_empty_zip
    empty_zip = create_empty_zip
    loader = RubyLlm::Skills::ZipLoader.new(empty_zip)

    assert_equal [], loader.list
  ensure
    File.delete(empty_zip) if empty_zip && File.exist?(empty_zip)
  end

  def test_from_zip_module_method
    loader = RubyLlm::Skills.from_zip(@zip_path)
    assert_instance_of RubyLlm::Skills::ZipLoader, loader
  end

  private

  def create_test_zip
    zip_path = File.join(Dir.tmpdir, "test_skills_#{Time.now.to_i}.zip")

    Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
      # Skill one with scripts
      zip.get_output_stream("zip-skill-one/SKILL.md") do |f|
        f.puts <<~SKILL
          ---
          name: zip-skill-one
          description: First zip skill
          ---
          # Zip Skill One

          Instructions for the first skill.
        SKILL
      end

      zip.get_output_stream("zip-skill-one/scripts/helper.rb") do |f|
        f.puts "# helper code"
      end

      # Skill two
      zip.get_output_stream("zip-skill-two/SKILL.md") do |f|
        f.puts <<~SKILL
          ---
          name: zip-skill-two
          description: Second zip skill
          ---
          # Zip Skill Two
        SKILL
      end
    end

    zip_path
  end

  def create_empty_zip
    zip_path = File.join(Dir.tmpdir, "empty_skills_#{Time.now.to_i}.zip")
    Zip::File.open(zip_path, Zip::File::CREATE) { |_| }
    zip_path
  end
end
