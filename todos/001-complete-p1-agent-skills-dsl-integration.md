---
status: complete
priority: p1
issue_id: "001"
tags: [ruby_llm, agent, skills, dsl]
dependencies: []
---

# Add skills DSL support to RubyLLM::Agent

Implement `RubyLLM::Skills::AgentExtensions` so `RubyLLM::Agent` classes can declare and apply skills via `skills` macro, matching existing chat/tool patterns.

## Problem Statement

`ruby_llm-skills` currently extends `RubyLLM::Chat` only. `RubyLLM::Agent` subclasses cannot declare skills via DSL, so users lose declarative configuration when moving to Agent-based workflows.

## Findings

- `RubyLLM::Agent` in ruby_llm 1.12.0 applies class DSL through singleton `apply_configuration`.
- The extension point is safe via singleton `prepend` and `super` chaining.
- `lib/ruby_llm/skills.rb` currently includes only `ChatExtensions`.
- Gem dependency is currently `ruby_llm >= 1.10`; Agent support requires 1.12+.

## Proposed Solutions

### Option 1: Add AgentExtensions with singleton prepend (selected)

**Approach:** Create `AgentExtensions` with class `skills` macro, instance `with_skills`, and singleton patch to call `apply_skills` after existing agent configuration.

**Pros:**
- Minimal and consistent with `Agent` DSL behavior
- Supports inheritance and runtime proc evaluation
- Keeps ChatExtensions unchanged

**Cons:**
- Depends on private Agent singleton helper methods

**Effort:** 2-4 hours

**Risk:** Low

## Recommended Action

Implement AgentExtensions, wire it in the entrypoint, bump dependency to RubyLLM >= 1.12, add unit/integration tests and README examples, then run tests + lint and open PR.

## Technical Details

**Affected files:**
- `lib/ruby_llm/skills/agent_extensions.rb`
- `lib/ruby_llm/skills.rb`
- `ruby_llm-skills.gemspec`
- `Gemfile.lock`
- `test/ruby_llm/skills/test_agent_extensions.rb`
- `test/ruby_llm/skills/test_agent_integration.rb`
- `README.md`
- `docs/plans/2026-02-17-feat-agent-skills-dsl-integration-plan.md`

## Acceptance Criteria

- [x] Add class-level `skills` macro with sources/only/block support
- [x] Add instance-level `with_skills` delegating to chat
- [x] Apply skills during Agent `apply_configuration`
- [x] Ensure inheritance/override behavior for skill config
- [x] Wire extension in `lib/ruby_llm/skills.rb`
- [x] Bump dependency to `ruby_llm >= 1.12`
- [x] Add unit tests for DSL and configuration behavior
- [x] Add integration coverage for Agent + skills flow
- [x] Update README with Agent usage
- [x] Run tests and standardrb successfully
- [x] Update plan checkboxes as tasks complete
- [x] Create commit and PR

## Work Log

### 2026-02-17 - Initialization

**By:** Codex

**Actions:**
- Read work plan and repository conventions
- Validated `ruby_llm` 1.12.0 Agent implementation from gem payload
- Created feature branch `feat/agent-skills-dsl-integration`
- Created execution todo file

**Learnings:**
- `Agent.apply_configuration` signature uses `input_values:` and `persist_instructions:` keywords
- Existing integration test strategy relies on VCR cassettes in `test/fixtures/vcr_cassettes`

### 2026-02-17 - Implementation and validation

**By:** Codex

**Actions:**
- Added `lib/ruby_llm/skills/agent_extensions.rb` with `skills` DSL, runtime `with_skills`, and singleton `apply_configuration` patch
- Wired extension in `lib/ruby_llm/skills.rb`
- Bumped `ruby_llm` dependency to `>= 1.12` and updated lockfile to 1.12.0
- Added a minimal `delegate` fallback shim for plain Ruby environments before requiring `ruby_llm`
- Added `test/ruby_llm/skills/test_agent_extensions.rb` and `test/ruby_llm/skills/test_agent_integration.rb`
- Updated README with `RubyLLM::Agent` usage examples
- Ran validation:
  - `bundle exec ruby -Itest test/ruby_llm/skills/test_agent_extensions.rb`
  - `bundle exec ruby -Itest test/ruby_llm/skills/test_agent_integration.rb`
  - `bundle exec rake test`
  - `bundle exec rake standard`
- Checked off acceptance criteria in plan doc

**Learnings:**
- `ruby_llm` 1.12.0 requires `delegate` availability for `Agent` in non-Rails environments
- Reusing existing VCR cassette (`with_skills_basic`) provides stable Agent integration coverage without new network recordings

### 2026-02-17 - Ship

**By:** Codex

**Actions:**
- Created commit `e2bb63f` with feature implementation
- Pushed branch `feat/agent-skills-dsl-integration`
- Opened PR: https://github.com/kieranklaassen/ruby_llm-skills/pull/2

**Learnings:**
- Existing untracked local artifacts can trigger GH CLI \"uncommitted change\" warnings without blocking PR creation
