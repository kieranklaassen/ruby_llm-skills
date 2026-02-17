---
status: complete
priority: p3
issue_id: "006"
tags: [code-review, docs, api, usability]
dependencies: []
---

# Runtime with_skills replaces class skills but docs imply additive behavior

`agent.with_skills("extra/skills")` replaces the existing `:skill` tool registration, while documentation text implies skills are being added.

## Problem Statement

Ambiguous API semantics can cause user confusion and hidden behavior changes in production agents.

## Findings

- `with_skills` delegates to chat and registers a `SkillTool` by name `:skill`.
- `Chat#with_tool` stores by tool name key, so second registration overwrites first.
- README example uses additive wording without explicit replace semantics.
- Evidence references:
  - `lib/ruby_llm/skills/agent_extensions.rb:55`
  - `lib/ruby_llm/skills/chat_extensions.rb:34`
  - `README.md:46`
  - `README.md:47`

## Proposed Solutions

### Option 1: Clarify docs and method contract (recommended)

**Approach:** Document replacement behavior explicitly and provide merging example in a single call.

**Pros:**
- Low effort
- Prevents confusion immediately

**Cons:**
- Does not change behavior

**Effort:** Small

**Risk:** Low

---

### Option 2: Add explicit `append:`/`replace:` option

**Approach:** Keep current default or switch default, but make semantics explicit in API.

**Pros:**
- Clearer runtime behavior
- Better ergonomics for advanced usage

**Cons:**
- Additional API complexity

**Effort:** Medium

**Risk:** Low

## Recommended Action


## Technical Details

**Affected files:**
- `README.md`
- `lib/ruby_llm/skills/agent_extensions.rb`
- `lib/ruby_llm/skills/chat_extensions.rb`

## Resources

- PR: https://github.com/kieranklaassen/ruby_llm-skills/pull/2

## Acceptance Criteria

- [x] Docs clearly state replacement vs additive semantics
- [x] Tests verify intended behavior for repeated `with_skills` calls
- [x] If API changes, migration guidance is documented

## Work Log

### 2026-02-17 - Code Review Finding

**By:** Codex

**Actions:**
- Traced tool registration path and overwrite behavior
- Compared behavior with README wording

**Learnings:**
- Explicit API semantics reduce downstream integration bugs

### 2026-02-17 - Resolution

**By:** Codex

**Actions:**
- Added README note clarifying that `agent.with_skills` replaces current skill-tool configuration
- Added regression test asserting replacement semantics

**Learnings:**
- Explicit docs and tests for overwrite behavior prevent ambiguous integration expectations
