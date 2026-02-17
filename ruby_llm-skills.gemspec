# frozen_string_literal: true

require_relative "lib/ruby_llm/skills/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_llm-skills"
  spec.version = RubyLLM::Skills::VERSION
  spec.authors = ["Kieran Klaassen"]
  spec.email = ["kieranklaassen@gmail.com"]

  spec.summary = "Agent Skills extension for RubyLLM"
  spec.description = "Load, validate, and integrate Agent Skills with RubyLLM. " \
                     "Supports the open Agent Skills specification for progressive " \
                     "skill discovery and loading from filesystem, zip archives, and databases."
  spec.homepage = "https://github.com/kieranklaassen/ruby_llm-skills"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kieranklaassen/ruby_llm-skills"
  spec.metadata["changelog_uri"] = "https://github.com/kieranklaassen/ruby_llm-skills/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*",
    "LICENSE.txt",
    "README.md",
    "CHANGELOG.md"
  ]
  spec.bindir = "exe"
  spec.executables = []
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby_llm", ">= 1.12"
  # rubyzip is optional for ZipLoader
end
