# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
