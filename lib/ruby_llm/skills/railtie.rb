# frozen_string_literal: true

module RubyLLM
  module Skills
    # Rails integration for RubyLLM::Skills.
    #
    # Sets up the default skills path to Rails.root/app/skills
    # and configures autoloading of skill files.
    #
    class Railtie < ::Rails::Railtie
      initializer "ruby_llm_skills.configure" do
        RubyLLM::Skills.default_path = Rails.root.join("app", "skills").to_s
      end

      # Add app/skills to autoload paths
      initializer "ruby_llm_skills.autoload_paths" do |app|
        skills_path = Rails.root.join("app", "skills")
        if skills_path.exist?
          app.config.autoload_paths << skills_path.to_s
        end
      end

      # Extend acts_as_chat models with skill methods
      initializer "ruby_llm_skills.active_record" do
        ActiveSupport.on_load(:active_record) do
          if defined?(RubyLLM::ActiveRecord::ChatMethods)
            RubyLLM::ActiveRecord::ChatMethods.include(RubyLLM::Skills::ActiveRecordExtensions)
          end
        end
      end

      # Provide rake tasks
      rake_tasks do
        load File.expand_path("tasks/skills.rake", __dir__)
      end
    end
  end
end
