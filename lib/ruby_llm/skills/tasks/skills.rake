# frozen_string_literal: true

# Under Rails the tasks load the environment first, so the default path is
# the application's. Rails defines :environment only after the railties'
# tasks are loaded, so the application is checked as well.
namespace :skills do
  prerequisites = (Rake::Task.task_defined?(:environment) || (defined?(Rails) && Rails.respond_to?(:application) && Rails.application)) ? [:environment] : []

  desc "List all available skills"
  task list: prerequisites do
    loader = RubyLLM::Skills.from_directory
    skills = loader.list

    if skills.empty?
      puts "No skills found in #{RubyLLM::Skills.default_path}"
      next
    end

    puts "Available skills (#{skills.count}):"
    puts ""

    skills.each do |skill|
      status = skill.valid? ? "✓" : "✗"
      puts "  #{status} #{skill.name}"
      puts "    #{skill.description}"
      puts ""
    end
  end

  desc "Validate all skills"
  task validate: prerequisites do
    loader = RubyLLM::Skills.from_directory
    skills = loader.list

    if skills.empty?
      puts "No skills found in #{RubyLLM::Skills.default_path}"
      next
    end

    valid_count = 0
    invalid_count = 0

    skills.each do |skill|
      if skill.valid?
        valid_count += 1
        puts "✓ #{skill.name}"
      else
        invalid_count += 1
        puts "✗ #{skill.name}"
        skill.errors.each do |error|
          puts "    - #{error}"
        end
      end
    end

    puts ""
    puts "#{valid_count} valid, #{invalid_count} invalid"

    exit(1) if invalid_count > 0
  end

  desc "Show details of a specific skill"
  task :show, [:name] => prerequisites do |_, args|
    name = args[:name]
    unless name
      puts "Usage: rake skills:show[skill-name]"
      exit(1)
    end

    loader = RubyLLM::Skills.from_directory
    skill = loader.find(name)

    unless skill
      puts "Skill '#{name}' not found"
      exit(1)
    end

    puts "Name: #{skill.name}"
    puts "Description: #{skill.description}"
    puts "License: #{skill.license || "(none)"}"
    puts "Compatibility: #{skill.compatibility || "(none)"}"
    puts "Path: #{skill.path}"
    puts "Valid: #{skill.valid? ? "yes" : "no"}"

    unless skill.errors.empty?
      puts ""
      puts "Errors:"
      skill.errors.each { |e| puts "  - #{e}" }
    end

    if skill.custom_metadata.any?
      puts ""
      puts "Metadata:"
      skill.custom_metadata.each { |k, v| puts "  #{k}: #{v}" }
    end

    if skill.scripts.any?
      puts ""
      puts "Scripts:"
      skill.scripts.each { |s| puts "  - #{s.delete_prefix("#{skill.path}/")}" }
    end

    if skill.references.any?
      puts ""
      puts "References:"
      skill.references.each { |r| puts "  - #{r.delete_prefix("#{skill.path}/")}" }
    end

    if skill.assets.any?
      puts ""
      puts "Assets:"
      skill.assets.each { |a| puts "  - #{a.delete_prefix("#{skill.path}/")}" }
    end
  end
end
