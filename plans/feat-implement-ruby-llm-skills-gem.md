# Implement RubyLLM::Skills Gem - Full Agent Skills Specification Support

## Overview

Implement a Ruby gem that extends RubyLLM with Agent Skills support following the [agentskills.io specification](https://agentskills.io/specification). The gem enables progressive disclosure of AI capabilities through skills loaded from multiple sources (filesystem, zip files, ActiveRecord models), with automatic Rails integration and comprehensive validation.

## Problem Statement / Motivation

**Current State:**
- RubyLLM provides unified LLM provider interface but no standardized way to extend capabilities
- Developers must manually inject instructions into system prompts
- No progressive disclosure - all context loaded upfront, wasting tokens
- Custom skills per-user requires custom implementation
- No validation framework for skill structure

**Why This Matters:**
- Agent Skills is an open standard adopted by Anthropic, OpenAI, Google
- Progressive disclosure reduces context usage by ~95% (100 tokens metadata vs 5k tokens full instructions)
- Multi-source loading enables per-user skill customization
- Standardized format makes skills portable across applications
- Validation ensures skills work correctly before deployment

**Business Value:**
- Reduces LLM API costs through efficient context usage
- Enables SaaS features (users create/upload custom skills)
- Improves agent capabilities through specialized knowledge
- Makes codebases more maintainable through separated concerns

## Proposed Solution

Implement a gem with these components:

### Core Architecture

**1. Skill Class (`lib/ruby_llm/skills/skill.rb`)**
- Represents single skill with metadata, content, resources
- Lazy-loading for progressive disclosure
- Validation methods following spec

**2. Loader System (`lib/ruby_llm/skills/loader.rb` + loaders/)**
- Base loader class with strategy pattern
- FilesystemLoader - Scan directories for skill folders
- ZipLoader - Extract and parse zip archives
- DatabaseLoader - Load from ActiveRecord models with format detection
- Multi-source support with override behavior (last wins)

**3. Validation System (`lib/ruby_llm/skills/validator.rb`)**
- Name format validation (lowercase, hyphens, length)
- Frontmatter validation (required fields, types, lengths)
- Directory structure validation
- Returns detailed error messages

**4. Module API (`lib/ruby_llm/skills.rb`)**
- `RubyLlm::Skills.default_path` - Config accessor
- `RubyLlm::Skills.logger` - Logger accessor
- `RubyLlm::Skills.load(from:)` - Load and return skills
- `RubyLlm::Skills.validate(skill)` - Validate structure
- `RubyLlm::Skills.find(name)` - Find specific skill

**5. Skill Tool (`lib/ruby_llm/skills/skill_tool.rb`)** ⚠️ CRITICAL
- Custom `RubyLLM::Tool` subclass for progressive skill loading
- **Description contains `<available_skills>` XML** with all loaded skill metadata
- **Parameter:** `command` (string) - the skill name to load
- **Returns:** Full SKILL.md content + skill path for resource access
- This is how the LLM triggers Level 2 (full instructions) loading
- Follows Anthropic's two-message pattern (visible loading message + hidden instructions)

**6. Skill Resource Tool (`lib/ruby_llm/skills/skill_resource_tool.rb`)** (Optional)
- Tool for loading resources (scripts, references, assets) on demand
- Enables Level 3 progressive disclosure
- Alternative: just return skill path and let LLM use existing Read tool

**7. RubyLLM Integration (`lib/ruby_llm/skills/chat_extensions.rb`)**
- Reopen `RubyLLM::Chat` class (following RubyLLM-MCP pattern)
- `chat.with_skills(from:, only:, except:)` - Load skills AND register Skill tool
- `chat.skills` - List loaded skills
- Automatically registers `SkillTool` with dynamic description

**8. Rails Integration (`lib/ruby_llm/skills/railtie.rb`)**
- Optional Railtie for auto-configuration
- Sets default_path to `Rails.root.join('app/skills')`
- Provides rake tasks and generators

## Technical Approach

### Implementation Phases

#### Phase 1: Core Skill & Parser (Week 1)

**Files to create:**
- `lib/ruby_llm/skills/skill.rb` - Skill class
- `lib/ruby_llm/skills/parser.rb` - YAML frontmatter parser
- `lib/ruby_llm/skills/error.rb` - Exception hierarchy
- `test/fixtures/skills/valid-skill/SKILL.md` - Test fixture
- `test/ruby_llm/test_skill.rb` - Skill tests

**Tasks:**
- [ ] Create `Skill` class with attributes: `name`, `description`, `content`, `path`, `metadata`
- [ ] Implement lazy `content` loading (only parse SKILL.md when accessed)
- [ ] Create `Parser.parse_frontmatter(path)` using stdlib YAML
- [ ] Extract frontmatter with regex: `/\A---\n(.*?)\n---\n(.+)/m`
- [ ] Use `YAML.safe_load` for security (permit only basic types)
- [ ] Handle malformed YAML gracefully (log warning, skip skill)
- [ ] Implement `skill.references`, `skill.scripts`, `skill.assets` as lazy-loaded arrays
- [ ] Create exception hierarchy: `Error < StandardError`, then `InvalidSkillError`, `NotFoundError`, `LoadError`
- [ ] Write comprehensive tests for valid/invalid frontmatter, missing files, malformed YAML

**Acceptance Criteria:**
- [ ] Can parse valid SKILL.md with frontmatter
- [ ] Returns `Skill` object with correct attributes
- [ ] Raises `InvalidSkillError` for malformed frontmatter
- [ ] Lazily loads content (doesn't read file until `.content` called)
- [ ] Handles missing optional fields gracefully

**Code Example:**

```ruby
# lib/ruby_llm/skills/skill.rb
module RubyLlm
  module Skills
    class Skill
      attr_reader :name, :description, :path, :metadata

      def initialize(path:, metadata:, content: nil)
        @path = path
        @metadata = metadata
        @name = metadata['name']
        @description = metadata['description']
        @content = content
      end

      def content
        @content ||= File.read(skill_md_path).split('---', 3).last.strip
      end

      def scripts
        @scripts ||= Dir.glob(File.join(path, 'scripts', '*'))
      end

      private

      def skill_md_path
        File.join(path, 'SKILL.md')
      end
    end
  end
end
```

#### Phase 2: Validation System (Week 1)

**Files to create:**
- `lib/ruby_llm/skills/validator.rb` - Validation logic
- `test/ruby_llm/test_validator.rb` - Validator tests
- `test/fixtures/skills/invalid-name/SKILL.md` - Invalid fixtures

**Tasks:**
- [ ] Create `Validator` class with `.validate(skill)` method
- [ ] Validate name format: `/\A[a-z0-9-]+\z/`, 1-64 chars, no consecutive hyphens
- [ ] Validate name matches directory basename
- [ ] Validate description: 1-1024 characters, non-empty
- [ ] Validate required fields present (name, description)
- [ ] Validate optional field types (license: string, compatibility: string, metadata: hash)
- [ ] Return errors array with specific messages: `["name contains uppercase letters"]`
- [ ] Implement `skill.valid?` convenience method
- [ ] Add `skill.errors` method returning validation errors
- [ ] Handle edge cases: Unicode in names, multi-byte characters in description

**Acceptance Criteria:**
- [ ] Validates name format correctly (lowercase, hyphens only)
- [ ] Rejects names >64 chars
- [ ] Rejects consecutive hyphens
- [ ] Validates description length (1-1024 chars)
- [ ] Returns specific error messages
- [ ] Validates directory name matches frontmatter name

**Code Example:**

```ruby
# lib/ruby_llm/skills/validator.rb
module RubyLlm
  module Skills
    class Validator
      NAME_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

      def self.validate(skill)
        errors = []

        # Name validation
        unless skill.name =~ NAME_FORMAT
          errors << "name must be lowercase letters, numbers, and hyphens only"
        end

        if skill.name.length > 64
          errors << "name must be 64 characters or less"
        end

        # Directory name match
        dir_name = File.basename(skill.path)
        if skill.name != dir_name
          errors << "name '#{skill.name}' must match directory name '#{dir_name}'"
        end

        # Description validation
        if skill.description.nil? || skill.description.empty?
          errors << "description is required"
        elsif skill.description.length > 1024
          errors << "description must be 1024 characters or less"
        end

        errors
      end
    end
  end
end
```

#### Phase 3: Filesystem Loader (Week 2)

**Files to create:**
- `lib/ruby_llm/skills/loader.rb` - Base loader class
- `lib/ruby_llm/skills/loaders/filesystem.rb` - Filesystem implementation
- `test/ruby_llm/loaders/test_filesystem.rb` - Filesystem tests

**Tasks:**
- [ ] Create base `Loader` class with `.load(source)` interface
- [ ] Implement `FilesystemLoader.load(path)` - scan directory
- [ ] Use `Pathname` for all path operations (cross-platform)
- [ ] Find all subdirectories containing `SKILL.md`
- [ ] For each skill directory, parse frontmatter (metadata only, not content)
- [ ] Create `Skill` object with lazy content loading
- [ ] Handle missing directories gracefully (log warning, return empty array)
- [ ] Handle permission errors (log error, skip directory)
- [ ] Validate SKILL.md exists in each skill directory
- [ ] Return array of `Skill` objects
- [ ] Support glob patterns for selective loading

**Acceptance Criteria:**
- [ ] Loads all skills from directory
- [ ] Skips directories without SKILL.md
- [ ] Handles nested directory structures
- [ ] Returns array of valid Skill objects
- [ ] Logs warnings for invalid skills
- [ ] Handles missing/unreadable directories

**Code Example:**

```ruby
# lib/ruby_llm/skills/loaders/filesystem.rb
module RubyLlm
  module Skills
    module Loaders
      class Filesystem < Loader
        def load(path)
          skills = []
          base_path = Pathname.new(path)

          return [] unless base_path.exist? && base_path.directory?

          base_path.children.each do |skill_dir|
            next unless skill_dir.directory?

            skill_md = skill_dir / 'SKILL.md'
            next unless skill_md.exist?

            begin
              metadata = Parser.parse_frontmatter(skill_md)
              skills << Skill.new(path: skill_dir.to_s, metadata: metadata)
            rescue => e
              logger&.warn "Failed to load skill from #{skill_dir}: #{e.message}"
            end
          end

          skills
        end
      end
    end
  end
end
```

#### Phase 4: Module API & Configuration (Week 2)

**Files to modify:**
- `lib/ruby_llm/skills.rb` - Main module entry point

**Tasks:**
- [ ] Add `class << self` with `attr_accessor :default_path, :logger`
- [ ] Set `self.default_path = "app/skills"`
- [ ] Implement `.load(from:)` - delegates to appropriate loader
- [ ] Add source type detection logic: string ends with `/` → filesystem, `.zip` → zip, responds to `each` → database
- [ ] Implement `.validate(skill)` - calls Validator
- [ ] Implement `.find(name, from: default_path)` - load and find by name
- [ ] Add `.validate_all(from: default_path)` - returns `{valid: [], invalid: []}`
- [ ] Conditional loading: `require_relative "skills/railtie" if defined?(Rails::Railtie)`
- [ ] Thread-safe configuration (use class instance variables, not class variables)

**Acceptance Criteria:**
- [ ] Can configure default_path globally
- [ ] Can set custom logger
- [ ] `.load` detects source type correctly
- [ ] `.find` locates skills by name
- [ ] `.validate_all` returns validation summary

**Code Example:**

```ruby
# lib/ruby_llm/skills.rb
require_relative "skills/version"
require_relative "skills/error"
require_relative "skills/skill"
require_relative "skills/parser"
require_relative "skills/validator"
require_relative "skills/loader"
require_relative "skills/loaders/filesystem"

module RubyLlm
  module Skills
    class << self
      attr_accessor :default_path, :logger
    end

    self.default_path = "app/skills"

    def self.load(from: default_path)
      source = from.is_a?(Array) ? from : [from]
      all_skills = []

      source.each do |src|
        loader = detect_loader(src)
        skills = loader.load(src)

        # Override: later sources replace earlier ones with same name
        skills.each do |skill|
          all_skills.reject! { |s| s.name == skill.name }
          all_skills << skill
        end
      end

      all_skills
    end

    def self.find(name, from: default_path)
      load(from: from).find { |s| s.name == name }
    end

    private

    def self.detect_loader(source)
      case source
      when String
        source.end_with?('.zip') ? Loaders::Zip : Loaders::Filesystem
      else
        Loaders::Database
      end
    end
  end
end
```

#### Phase 5: Zip Loader (Week 3)

**Files to create:**
- `lib/ruby_llm/skills/loaders/zip.rb` - Zip implementation
- `test/ruby_llm/loaders/test_zip.rb` - Zip tests
- `test/fixtures/skills.zip` - Test zip file

**Dependencies:**
- Add `rubyzip` ~> 3.0 to gemspec

**Tasks:**
- [ ] Add `spec.add_dependency "rubyzip", "~> 3.0"` to gemspec
- [ ] Implement `ZipLoader.load(zip_path)`
- [ ] Extract zip to temporary directory using `Dir.mktmpdir`
- [ ] Scan extracted directory using FilesystemLoader
- [ ] Validate zip structure (skill directories at root level)
- [ ] Add zip bomb protection: check entry sizes before extraction, reject if >100MB total
- [ ] Handle corrupted zip files gracefully (log error, return empty array)
- [ ] Clean up temporary directory after loading
- [ ] Keep temp directory available during chat lifetime for resource access
- [ ] Add tests for multi-skill zips, single-skill zips, invalid zips

**Acceptance Criteria:**
- [ ] Extracts zip to temp directory
- [ ] Loads all skills from zip
- [ ] Cleans up temp directory appropriately
- [ ] Protects against zip bombs
- [ ] Handles corrupted zips gracefully

**Code Example:**

```ruby
# lib/ruby_llm/skills/loaders/zip.rb
require 'zip'
require 'tmpdir'

module RubyLlm
  module Skills
    module Loaders
      class Zip < Loader
        MAX_EXTRACTION_SIZE = 100 * 1024 * 1024 # 100MB

        def load(zip_path)
          validate_zip_size(zip_path)

          Dir.mktmpdir('ruby_llm_skills') do |temp_dir|
            extract_zip(zip_path, temp_dir)
            Filesystem.new(logger: logger).load(temp_dir)
          end
        end

        private

        def validate_zip_size(zip_path)
          total_size = 0

          ::Zip::File.open(zip_path) do |zip_file|
            zip_file.each do |entry|
              total_size += entry.size
              if total_size > MAX_EXTRACTION_SIZE
                raise LoadError, "Zip file too large (>100MB uncompressed)"
              end
            end
          end
        end

        def extract_zip(zip_path, dest)
          ::Zip::File.open(zip_path) do |zip_file|
            zip_file.each do |entry|
              entry_path = File.join(dest, entry.name)
              FileUtils.mkdir_p(File.dirname(entry_path))
              entry.extract(entry_path)
            end
          end
        end
      end
    end
  end
end
```

#### Phase 6: Database Loader (Week 3)

**Files to create:**
- `lib/ruby_llm/skills/loaders/database.rb` - Database implementation
- `test/ruby_llm/loaders/test_database.rb` - Database tests

**Tasks:**
- [ ] Implement `DatabaseLoader.load(records)` - accepts enumerable
- [ ] Use duck-typing: check for `each`, not `ActiveRecord::Relation`
- [ ] Detect storage format: `respond_to?(:content)` vs `respond_to?(:data)`
- [ ] For text format: parse content as SKILL.md (extract frontmatter)
- [ ] For binary format: treat data as zip, extract and load
- [ ] Create virtual Skill objects (path is database ID or record identifier)
- [ ] Handle records missing required fields gracefully
- [ ] Log warnings for invalid records
- [ ] Support any ORM (ActiveRecord, Sequel, ROM) via duck-typing
- [ ] Add comprehensive tests with mock records

**Acceptance Criteria:**
- [ ] Loads skills from enumerable of objects
- [ ] Detects text vs binary storage format
- [ ] Handles both ActiveRecord and plain objects
- [ ] Gracefully handles invalid records
- [ ] Logs warnings for skipped records

**Code Example:**

```ruby
# lib/ruby_llm/skills/loaders/database.rb
module RubyLlm
  module Skills
    module Loaders
      class Database < Loader
        def load(records)
          skills = []

          records.each do |record|
            skill = load_record(record)
            skills << skill if skill
          rescue => e
            logger&.warn "Failed to load skill from record #{record.id}: #{e.message}"
          end

          skills
        end

        private

        def load_record(record)
          if record.respond_to?(:content) && record.content.present?
            load_text_record(record)
          elsif record.respond_to?(:data) && record.data.present?
            load_binary_record(record)
          else
            logger&.warn "Skill record #{record.id} has neither content nor data"
            nil
          end
        end

        def load_text_record(record)
          metadata = Parser.parse_frontmatter_string(record.content)
          Skill.new(
            path: "database:#{record.id}",
            metadata: metadata,
            content: record.content
          )
        end

        def load_binary_record(record)
          Dir.mktmpdir('ruby_llm_skill') do |temp_dir|
            zip_path = File.join(temp_dir, "skill.zip")
            File.binwrite(zip_path, record.data)
            Zip.new(logger: logger).load(zip_path).first
          end
        end
      end
    end
  end
end
```

#### Phase 7: Skill Tool & Chat Integration (Week 4) ⚠️ CRITICAL

This phase implements the **core progressive disclosure mechanism** - the Skill tool that allows the LLM to load full skill instructions on demand.

**Files to create:**
- `lib/ruby_llm/skills/skill_tool.rb` - The Skill tool (inherits from RubyLLM::Tool)
- `lib/ruby_llm/skills/chat_extensions.rb` - Chat integration (reopens RubyLLM::Chat)
- `test/ruby_llm/test_skill_tool.rb` - Skill tool tests
- `test/ruby_llm/test_chat_integration.rb` - Integration tests

**How Progressive Disclosure Works:**

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. chat.with_skills(from: "app/skills")                         │
│    └── Loads skill metadata (~100 tokens each)                  │
│    └── Creates SkillTool with <available_skills> in description │
│    └── Registers SkillTool via chat.with_tool(skill_tool)       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. chat.ask("Create a PDF report from this data")               │
│    └── LLM sees SkillTool description with <available_skills>   │
│    └── LLM matches "PDF report" to pdf-report skill description │
│    └── LLM calls: Skill tool with command: "pdf-report"         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. SkillTool.execute(command: "pdf-report")                     │
│    └── Returns full SKILL.md content (~5000 tokens)             │
│    └── Returns skill path for resource access                   │
│    └── LLM now has detailed instructions                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. LLM executes skill instructions                              │
│    └── May use Read tool to load scripts/references from path   │
│    └── Level 3 resources loaded only when needed                │
└─────────────────────────────────────────────────────────────────┘
```

**Tasks:**

**A. Implement SkillTool (`lib/ruby_llm/skills/skill_tool.rb`):**
- [ ] Create `SkillTool` class inheriting from `RubyLLM::Tool`
- [ ] Initialize with array of loaded skills
- [ ] Generate dynamic description with `<available_skills>` XML
- [ ] Define `command` parameter (string, required) - the skill name
- [ ] Implement `execute(command:)` - returns skill content + path
- [ ] Handle unknown skill gracefully (return error message, don't raise)
- [ ] Include skill path in response for resource access

**B. Implement Chat Extensions (`lib/ruby_llm/skills/chat_extensions.rb`):**
- [ ] Reopen `RubyLLM::Chat` class (following RubyLLM-MCP pattern)
- [ ] Implement `with_skills(from:, only:, except:)` method
- [ ] Load skills and create SkillTool instance
- [ ] Register SkillTool via `with_tool(skill_tool)`
- [ ] Store skills in `@loaded_skills` for introspection
- [ ] Implement `skills` accessor
- [ ] Make additive: multiple calls update SkillTool with merged skills

**Acceptance Criteria:**
- [ ] SkillTool has dynamic description with all available skills
- [ ] LLM can call Skill tool to load full instructions
- [ ] Skill content is returned when tool is invoked
- [ ] Unknown skill names return helpful error
- [ ] Multiple `with_skills` calls properly update the tool
- [ ] Works with all RubyLLM providers (OpenAI, Anthropic, Gemini, etc.)

**Code Example - SkillTool:**

```ruby
# lib/ruby_llm/skills/skill_tool.rb
# frozen_string_literal: true

module RubyLlm
  module Skills
    # Tool that enables progressive skill loading via LLM tool calls.
    # The LLM reads available skills from the description and calls
    # this tool to load full instructions when needed.
    class SkillTool < RubyLLM::Tool
      attr_reader :skills

      def initialize(skills)
        @skills = skills.index_by(&:name)
        super()
      end

      # Dynamic description includes all available skills
      def description
        <<~DESC
          Load skill instructions for specialized tasks.

          Call this tool when you need detailed instructions for a skill.
          The skill name should match one of the available skills below.

          #{available_skills_xml}
        DESC
      end

      param :command, type: 'string', desc: 'The skill name to load (e.g., "pdf-report")', required: true

      def execute(command:)
        skill = skills[command]

        unless skill
          return {
            success: false,
            error: "Unknown skill '#{command}'. Available: #{skills.keys.join(', ')}"
          }
        end

        {
          success: true,
          skill_name: skill.name,
          skill_path: skill.path,
          instructions: skill.content
        }
      end

      private

      def available_skills_xml
        xml = "<available_skills>\n"
        skills.each_value do |skill|
          xml << "  <skill>\n"
          xml << "    <name>#{escape_xml(skill.name)}</name>\n"
          xml << "    <description>#{escape_xml(skill.description)}</description>\n"
          xml << "    <location>#{escape_xml(skill.path)}</location>\n"
          xml << "  </skill>\n"
        end
        xml << "</available_skills>"
        xml
      end

      def escape_xml(text)
        text.to_s
          .gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub('"', '&quot;')
          .gsub("'", '&apos;')
      end
    end
  end
end
```

**Code Example - Chat Extensions:**

```ruby
# lib/ruby_llm/skills/chat_extensions.rb
# frozen_string_literal: true

# Reopen RubyLLM::Chat to add skills support
# Following the pattern used by RubyLLM::MCP
module RubyLLM
  class Chat
    attr_reader :loaded_skills

    # Load skills and register the Skill tool for progressive disclosure.
    #
    # @param from [String, Array, ActiveRecord::Relation] skill source(s)
    # @param only [Array<Symbol>] whitelist of skill names
    # @param except [Array<Symbol>] blacklist of skill names
    # @return [self] for method chaining
    def with_skills(from: nil, only: nil, except: nil)
      if only && except
        raise ArgumentError, "Cannot specify both 'only' and 'except'"
      end

      from ||= RubyLlm::Skills.default_path
      skills = RubyLlm::Skills.load(from: from)

      # Apply filters
      skills = skills.select { |s| only.include?(s.name.to_sym) } if only
      skills = skills.reject { |s| except.include?(s.name.to_sym) } if except

      # Merge with existing skills (override by name)
      @loaded_skills ||= {}
      skills.each do |skill|
        if @loaded_skills.key?(skill.name)
          RubyLlm::Skills.logger&.info "Skill '#{skill.name}' overridden"
        end
        @loaded_skills[skill.name] = skill
      end

      # Create and register the Skill tool with all loaded skills
      skill_tool = RubyLlm::Skills::SkillTool.new(@loaded_skills.values)
      with_tool(skill_tool)

      self
    end

    # Returns array of loaded skill objects
    def skills
      (@loaded_skills || {}).values
    end
  end
end
```

**Test Example:**

```ruby
# test/ruby_llm/test_skill_tool.rb
require "test_helper"

class TestSkillTool < Minitest::Test
  def setup
    @skill = RubyLlm::Skills::Skill.new(
      path: "test/fixtures/skills/pdf-report",
      metadata: { "name" => "pdf-report", "description" => "Generate PDF reports" }
    )
    @tool = RubyLlm::Skills::SkillTool.new([@skill])
  end

  def test_description_includes_available_skills
    assert_includes @tool.description, "<available_skills>"
    assert_includes @tool.description, "pdf-report"
    assert_includes @tool.description, "Generate PDF reports"
  end

  def test_execute_returns_skill_content
    result = @tool.execute(command: "pdf-report")

    assert result[:success]
    assert_equal "pdf-report", result[:skill_name]
    assert_includes result[:instructions], "#" # SKILL.md content
  end

  def test_execute_unknown_skill_returns_error
    result = @tool.execute(command: "unknown-skill")

    refute result[:success]
    assert_includes result[:error], "Unknown skill"
    assert_includes result[:error], "pdf-report" # Shows available skills
  end

  def test_has_command_parameter
    assert @tool.parameters.key?(:command)
    assert @tool.parameters[:command].required
  end
end
```

#### Phase 8: Rails Integration (Week 4)

**Files to create:**
- `lib/ruby_llm/skills/railtie.rb` - Rails integration
- `lib/generators/skill/skill_generator.rb` - Skill generator
- `lib/generators/skill/USAGE` - Generator usage
- `lib/generators/skill/templates/SKILL.md.tt` - Template

**Tasks:**
- [ ] Create `Railtie` class inheriting from `Rails::Railtie`
- [ ] Add initializer to set default_path to `Rails.root.join('app/skills')`
- [ ] Add rake task: `rake skills:validate` - validates all skills in app/skills
- [ ] Add rake task: `rake skills:list` - lists all available skills
- [ ] Create generator: `rails generate skill NAME` - creates skill directory structure
- [ ] Generator creates: `app/skills/NAME/SKILL.md`, `scripts/`, `references/`, `assets/`
- [ ] Generator template includes frontmatter with name/description placeholders
- [ ] Add console helpers if needed
- [ ] Support Rails development mode reloading (optional, may require manual restart)
- [ ] Conditional loading: only load Railtie if `Rails::Railtie` is defined

**Acceptance Criteria:**
- [ ] Railtie loads automatically in Rails apps
- [ ] Default path set to Rails.root/app/skills
- [ ] Rake tasks work correctly
- [ ] Generator creates valid skill structure
- [ ] Non-Rails apps work without Railtie

**Code Example:**

```ruby
# lib/ruby_llm/skills/railtie.rb
module RubyLlm
  module Skills
    class Railtie < Rails::Railtie
      initializer "ruby_llm_skills.configure" do |app|
        RubyLlm::Skills.default_path = Rails.root.join('app', 'skills')
        RubyLlm::Skills.logger = Rails.logger
      end

      rake_tasks do
        load "tasks/skills.rake"
      end

      generators do
        require "generators/skill/skill_generator"
      end
    end
  end
end
```

```ruby
# lib/generators/skill/skill_generator.rb
require 'rails/generators'

module RubyLlm
  module Skills
    class SkillGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      def create_skill_structure
        template "SKILL.md.tt", "app/skills/#{file_name}/SKILL.md"
        create_file "app/skills/#{file_name}/scripts/.keep"
        create_file "app/skills/#{file_name}/references/.keep"
        create_file "app/skills/#{file_name}/assets/.keep"
      end
    end
  end
end
```

### Alternative Approaches Considered

**1. Use `front_matter_parser` gem vs stdlib YAML**
- **Chosen:** stdlib YAML with regex extraction
- **Rejected:** Additional dependency for minimal benefit
- **Rationale:** Keep gem lightweight, YAML parsing is simple, stdlib sufficient

**2. Eager vs Lazy Loading of SKILL.md Content**
- **Chosen:** Lazy loading (parse metadata immediately, content on-demand)
- **Alternative:** Eager loading (parse everything upfront)
- **Rationale:** Progressive disclosure is core feature, aligns with spec philosophy

**3. ActiveRecord Hard Dependency vs Duck Typing**
- **Chosen:** Duck typing (any enumerable with expected methods)
- **Alternative:** Require ActiveRecord, use AR-specific features
- **Rationale:** Broader compatibility, simpler testing, follows Andrew Kane pattern

**4. Monkey-Patch vs Refinements for Chat Integration**
- **Chosen:** Monkey-patch with module include
- **Alternative:** Ruby refinements
- **Rationale:** Refinements require `using` in every file, less ergonomic for gem users

**5. Global Skill Cache vs Per-Chat Cache**
- **Chosen:** Per-chat instance storage
- **Alternative:** Global cache with memoization
- **Rationale:** Better memory management, supports different skill sets per chat

## Acceptance Criteria

### Functional Requirements

- [ ] **Multi-Source Loading:** Can load skills from filesystem directories, zip files, and database records
- [ ] **Format Detection:** Automatically detects source type (filesystem, zip, database text, database binary)
- [ ] **Override Behavior:** Later sources override earlier sources when names collide
- [ ] **Filtering:** Supports `only` and `except` parameters to selectively load skills
- [ ] **Validation:** Validates skill structure per agentskills.io spec
- [ ] **Progressive Disclosure:** Loads metadata immediately, content lazily
- [ ] **Rails Integration:** Automatic setup via Railtie in Rails apps
- [ ] **Non-Rails Support:** Works standalone without Rails dependency

### Non-Functional Requirements

- [ ] **Performance:** Loads 100 skills with metadata in <100ms
- [ ] **Memory:** Metadata-only mode uses <1KB per skill
- [ ] **Thread Safety:** Safe for concurrent use in multi-threaded servers
- [ ] **Ruby Compatibility:** Works on Ruby 3.1+
- [ ] **Zero Runtime Dependencies:** Only development dependencies (testing, linting)
- [ ] **Logging:** Comprehensive logging at appropriate levels (DEBUG, INFO, WARN, ERROR)

### Quality Gates

- [ ] **Test Coverage:** >90% line coverage via SimpleCov
- [ ] **Linting:** Passes `bundle exec rake standard` with zero violations
- [ ] **Documentation:** All public methods documented with YARD comments
- [ ] **Fixtures:** Comprehensive test fixtures covering valid/invalid cases
- [ ] **Integration Tests:** End-to-end tests with RubyLLM (may require mocking)

## Success Metrics

**Quantitative:**
- Parse 100 skills in <100ms (performance)
- Metadata uses <100 tokens per skill (efficiency)
- Test coverage >90% (quality)
- Zero StandardRB violations (code quality)

**Qualitative:**
- README examples work without modification
- Integration feels natural to RubyLLM users
- Error messages are clear and actionable
- Works smoothly in Rails and non-Rails contexts

## Dependencies & Risks

### Dependencies

**Required:**
- `rubyzip` ~> 3.0 (zip file handling)

**Development:**
- `minitest` (testing)
- `standard` (linting)
- `simplecov` (coverage)

**Optional:**
- `rails` >= 6.0 (for Railtie integration)
- `activerecord` >= 6.0 (for database loading)

### Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| RubyLLM API incompatibility | High | Medium | Research RubyLLM source early, contact maintainer if needed |
| Agent Skills spec changes | Medium | Low | Monitor spec repo, version gem accordingly |
| Performance with large skill sets | Medium | Medium | Benchmark early, optimize if needed |
| Database record format variance | Medium | Medium | Use duck typing, provide clear documentation |
| Zip bomb attacks | High | Low | Validate zip sizes before extraction |
| Path traversal attacks | High | Low | Sanitize all paths, validate no `../` escaping |

## Research & References

### Internal References

- `/Users/kieranklaassen/ruby_llm-skills/README.md` - Gem specification and API examples
- `/Users/kieranklaassen/ruby_llm-skills/RESEARCH.md` - Comprehensive research notes
- `/Users/kieranklaassen/ruby_llm-skills/CLAUDE.md` - Project conventions
- `/Users/kieranklaassen/ruby_llm-skills/lib/ruby_llm/skills.rb:1-10` - Current skeleton
- `/Users/kieranklaassen/ruby_llm-skills/Rakefile:10` - Default rake task configuration
- `/Users/kieranklaassen/ruby_llm-skills/test/test_helper.rb:1-6` - Test setup pattern

### External References

**Official Specifications:**
- [Agent Skills Specification](https://agentskills.io/specification) - Official spec
- [Anthropic Skills Repository](https://github.com/anthropics/skills) - Example skills
- [Anthropic Engineering Blog](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) - Design philosophy

**Ruby/Rails Documentation:**
- [Ruby YAML/Psych](https://docs.ruby-lang.org/en/master/Psych.html) - Frontmatter parsing
- [rubyzip gem](https://github.com/rubyzip/rubyzip) - Zip file handling
- [Rails Railtie API](https://api.rubyonrails.org/classes/Rails/Railtie.html) - Rails integration
- [Pathname](https://docs.ruby-lang.org/en/master/Pathname.html) - Path operations

**Best Practices:**
- [Andrew Kane Gem Patterns](https://ankane.org/gem-patterns) - Gem architecture
- [Minitest Style Guide](https://minitest.rubystyle.guide/) - Testing patterns
- [StandardRB](https://github.com/standardrb/standard) - Code style

**Technical Deep Dives:**
- [Claude Skills Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/) - How skills work
- [Inside Claude Code Skills](https://mikhail.io/2025/10/claude-code-skills/) - Implementation details

### Related Work

- [RubyLLM](https://github.com/crmne/ruby_llm) - Base gem we're extending
- [RubyLLM::MCP](https://github.com/patvice/ruby_llm-mcp) - Reference for extension patterns

## Implementation Notes

### Security Considerations

1. **Path Traversal Prevention:**
   - Validate all paths don't contain `../`
   - Use `File.expand_path` and verify results stay within base directory
   - Never trust user-provided paths without validation

2. **Zip Bomb Protection:**
   - Check total uncompressed size before extraction
   - Limit to 100MB uncompressed
   - Validate compression ratio (reject if >100:1)

3. **YAML Safety:**
   - Always use `YAML.safe_load`, never `YAML.load`
   - Permit only basic types: `[Symbol]`
   - Catch and handle YAML parsing exceptions

4. **Database Input Validation:**
   - Validate record fields before processing
   - Handle missing/malformed data gracefully
   - Log suspicious patterns

### Testing Strategy

**Unit Tests:**
- Parser: valid/invalid frontmatter, missing fields, malformed YAML
- Validator: all spec rules, edge cases, Unicode handling
- Skill: lazy loading, attribute access, resource discovery
- Loaders: filesystem, zip, database - valid/invalid inputs

**Integration Tests:**
- Multi-source loading with overrides
- Chat integration (with mocked RubyLLM)
- Rails integration (with dummy Rails app)
- End-to-end workflows

**Fixtures:**
```
test/fixtures/skills/
├── valid-skill/SKILL.md
├── invalid-name/SKILL.md (uppercase name)
├── missing-description/SKILL.md
├── with-scripts/
│   ├── SKILL.md
│   └── scripts/generate.rb
└── with-all-resources/
    ├── SKILL.md
    ├── scripts/
    ├── references/
    └── assets/
```

### Documentation Requirements

- [ ] Update README.md with installation, quick start, full API reference
- [ ] Create CHANGELOG.md following Keep a Changelog format
- [ ] Add LICENSE file (MIT, match ecosystem)
- [ ] Complete gemspec TODO placeholders (summary, description, URLs)
- [ ] Add inline YARD documentation for all public methods
- [ ] Create example Rails app in `examples/` directory
- [ ] Document database schema with indexes and constraints
- [ ] Add troubleshooting section to README

### Completion Checklist

**Before first release (v0.1.0):**
- [ ] All phases implemented
- [ ] Test coverage >90%
- [ ] StandardRB passing
- [ ] README complete with examples
- [ ] CHANGELOG created
- [ ] LICENSE file added
- [ ] Gemspec completed
- [ ] Example Rails app created
- [ ] Security review completed
- [ ] Performance benchmarks run
- [ ] Integration tested with real RubyLLM

**Known Limitations:**
- Requires manual restart in Rails development mode (no auto-reload)
- System prompt injection mechanism TBD based on RubyLLM API
- Skill triggering protocol TBD based on RubyLLM tool system
- No built-in skill versioning (relies on application layer)

---

**Plan Status:** Ready for review
**Estimated Complexity:** Large (4 weeks, phased implementation)
**Priority:** High (core functionality for gem)
