# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0.pre2] - 2026-09-14

### Changed

- Updated the RubyLLM 2.0 dependency floor and development locks from `2.0.0.rc2` to `2.0.0.rc3`
- Verified the Agent Skills integration against RubyLLM 2.0.0.rc3; its Agent, Chat, and Tool APIs remain compatible with the 0.4 port

## [0.4.0.pre1] - 2026-09-10

### Changed

- **Breaking:** requires RubyLLM 2.0 (`ruby_llm >= 2.0.0.rc2, < 3`); 1.x users should stay on 0.3.x
- `SkillTool` declares parameters with the 2.0 `parameter`/`description:` DSL, exposes `parameters_schema`, and sets its name through `tool_name`
- `Chat#with_skills` registers the skill tool via `Chat#with_tools` (2.0 removed `Chat#with_tool`)
- `AgentExtensions` hooks the 2.0 `Agent.apply_configuration(chat, input_values:, persist_instructions:)` signature and applies skills to the chat or `acts_as_chat` record it receives
- Integration tests pin `openai_protocol = :chat_completions` and match VCR cassettes on method and URI so the recorded 1.x interactions replay under 2.0

### Removed

- Global `Module#delegate` fallback and its compatibility test (2.0's `Agent` uses `Forwardable`)
- Dependency on the removed `Agent.llm_chat_for` hook

### Fixed

- StandardRB `Layout/EmptyLinesAroundModuleBody` offense in `chat_extensions.rb` that failed CI

## [0.3.0] - 2026-02-17

### Added

- `RubyLLM::Agent` integration via `RubyLLM::Skills::AgentExtensions`
- Class-level `skills` DSL on agent subclasses with source, `only:`, and proc support
- Instance-level `with_skills` for runtime agent skill configuration
- Agent-specific unit and integration test coverage
- Compatibility tests for delegate fallback behavior

### Changed

- Tightened `ruby_llm` dependency from open lower bound to `~> 1.12`
- Added explicit runtime compatibility checks for required `RubyLLM::Agent` hooks
- Documented `agent.with_skills(...)` replacement semantics in README

### Fixed

- Dynamic skill blocks resolving to `nil` or `[]` no longer silently load default skills
- Skill source normalization and validation now prevent nested/invalid source runtime crashes
- Delegate fallback now supports common delegation options (`prefix`, `allow_nil`, `private`)

## [0.1.0] - 2025-01-15

### Added

- Initial release with full Agent Skills specification support
- `Parser` - YAML frontmatter parsing with safe_load
- `Skill` - Lazy loading for content and resources
- `Validator` - Agent Skills spec validation rules
- `FilesystemLoader` - Directory-based skill loading
- `ZipLoader` - Archive-based skill loading (optional rubyzip dependency)
- `DatabaseLoader` - Duck-typed record loading (text or binary storage)
- `CompositeLoader` - Multi-source skill combination
- `SkillTool` - RubyLLM tool with progressive disclosure via dynamic description
- `ChatExtensions` - `with_skills()` and `with_skill_loader()` convenience methods
- Rails integration with Railtie, generator, and rake tasks
- Comprehensive test suite (142 tests)
