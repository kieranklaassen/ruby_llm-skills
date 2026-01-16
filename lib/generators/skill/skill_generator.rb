# frozen_string_literal: true

require "rails/generators"

class SkillGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  class_option :description, type: :string, default: "Description of what this skill does"
  class_option :license, type: :string, default: nil
  class_option :scripts, type: :boolean, default: false
  class_option :references, type: :boolean, default: false
  class_option :assets, type: :boolean, default: false

  def create_skill_directory
    empty_directory skill_path
  end

  def create_skill_md
    template "SKILL.md.tt", File.join(skill_path, "SKILL.md")
  end

  def create_scripts_directory
    return unless options[:scripts]

    empty_directory File.join(skill_path, "scripts")
    create_file File.join(skill_path, "scripts", ".keep")
  end

  def create_references_directory
    return unless options[:references]

    empty_directory File.join(skill_path, "references")
    create_file File.join(skill_path, "references", ".keep")
  end

  def create_assets_directory
    return unless options[:assets]

    empty_directory File.join(skill_path, "assets")
    create_file File.join(skill_path, "assets", ".keep")
  end

  private

  def skill_path
    File.join("app", "skills", skill_name)
  end

  def skill_name
    file_name.downcase.tr("_", "-").gsub(/[^a-z0-9-]/, "")
  end

  def skill_description
    options[:description]
  end

  def skill_license
    options[:license]
  end
end
