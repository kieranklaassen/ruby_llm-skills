# frozen_string_literal: true

# Plugin marketplaces from the command line:
#
#   rake skills:marketplaces:add[EveryInc/compound-writing]        # record a marketplace
#   rake skills:marketplaces:add[typesafe-ai/skills,v0.5.7]        # pinned to a tag or commit
#   rake skills:marketplaces:list                                  # what is recorded and installed
#   rake skills:marketplaces:plugins[compound-writing]             # the plugins a marketplace lists
#   rake skills:marketplaces:install[compound-writing]             # every supported plugin
#   rake skills:marketplaces:install[compound-writing,cw-draft]    # selected plugins (space separated)
#   rake skills:marketplaces:install                               # reproduce the lockfile
#   rake skills:marketplaces:update                                # move unpinned marketplaces forward
#   rake skills:marketplaces:remove[compound-writing]
#
# Under Rails the tasks load the environment first, so the root and lockfile
# resolve against Rails.root.
namespace :skills do
  namespace :marketplaces do
    prerequisites = Rake::Task.task_defined?(:environment) ? [:environment] : []

    registry = -> { RubyLLM::Skills.marketplaces }

    report = lambda do |result|
      result.installed.each { |key| puts "  + #{key}" }
      result.updated.each { |key| puts "  ~ #{key}" }
      result.unchanged.each { |key| puts "  = #{key}" }
      result.skipped.each { |key, reason| puts "  - #{key}: #{reason}" }
      result.errors.each { |key, message| puts "  ! #{key}: #{message}" }
      abort("#{result.errors.size} plugin(s) failed") unless result.success?
    end

    desc "Add a marketplace (owner/repo, owner/repo@ref, repository URL, hosted marketplace.json URL, or directory)"
    task :add, [:locator, :ref] => prerequisites do |_, args|
      abort("Usage: rake skills:marketplaces:add[locator,ref]") unless args[:locator]

      record = registry.call.add(args[:locator], ref: args[:ref])
      puts "Added #{record.name} from #{record.source} at #{record.commit[0, 12]}"
      puts "Install with: rake skills:marketplaces:install[#{record.name}]"
    end

    desc "List the recorded marketplaces and their installed plugins"
    task list: prerequisites do
      records = registry.call.list
      if records.empty?
        puts "No marketplaces in #{registry.call.lockfile_path}"
        next
      end

      records.each do |record|
        pin = record.pinned? ? " (pinned)" : ""
        puts "#{record.name}  #{record.source}  @#{record.commit.to_s[0, 12]}#{pin}"
        record.plugins.each_value do |plugin|
          puts "  #{plugin.name} #{plugin.version}  skills: #{plugin.skills.join(", ")}"
        end
      end
    end

    desc "List the plugins a marketplace offers"
    task :plugins, [:name] => prerequisites do |_, args|
      abort("Usage: rake skills:marketplaces:plugins[marketplace]") unless args[:name]

      record = registry.call.fetch(args[:name])
      registry.call.plugins(record.name).each do |entry|
        state = if record.plugins.key?(entry.name)
          "installed"
        elsif entry.supported?
          "available"
        else
          "unsupported (#{entry.source.reason})"
        end
        puts "#{entry.name}  #{entry.version || "-"}  #{state}"
        puts "  #{entry.description}" if entry.description
      end
    end

    desc "Install a marketplace's plugins (all, or the space separated names), or reproduce the lockfile"
    task :install, [:name, :plugins] => prerequisites do |_, args|
      only = args[:plugins]&.split
      report.call(registry.call.install(args[:name], only: only))
    end

    desc "Update every marketplace (or one) to its ref's current head"
    task :update, [:name] => prerequisites do |_, args|
      report.call(registry.call.update(args[:name]))
    end

    desc "Remove a marketplace and its installed plugins"
    task :remove, [:name] => prerequisites do |_, args|
      abort("Usage: rake skills:marketplaces:remove[marketplace]") unless args[:name]

      record = registry.call.remove(args[:name])
      puts "Removed #{record.name}"
    end
  end
end
