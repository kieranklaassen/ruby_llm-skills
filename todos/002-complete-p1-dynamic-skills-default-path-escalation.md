---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, security, agent, ruby_llm, correctness]
dependencies: []
---

# Dynamic skills nil/empty falls back to default path

A dynamic `skills { ... }` block that resolves to `nil` or `[]` still registers skills from `RubyLLM::Skills.default_path`, which can expose capabilities that should be disabled.

## Problem Statement

The Agent DSL should allow request-time logic to disable skills. Current behavior silently loads default skills instead, breaking least-privilege expectations.

## Findings

- `AgentExtensions#apply_skills` always calls `with_skills(*Array(resolved_sources), ...)`.
- `ChatExtensions#with_skills` treats no sources as default path.
- Reproduction confirms `skills { nil }` still exposes `valid-skill` when default path points to fixtures.
- Evidence references:
  - `lib/ruby_llm/skills/agent_extensions.rb:76`
  - `lib/ruby_llm/skills/agent_extensions.rb:82`
  - `lib/ruby_llm/skills/chat_extensions.rb:28`

## Proposed Solutions

### Option 1: Guard empty resolved sources (recommended)

**Approach:** In `apply_skills`, return early when resolved sources are `nil`/empty.

**Pros:**
- Preserves intent of dynamic “no skills” configuration
- Minimal code change
- No global behavior changes

**Cons:**
- Slight behavior change for callers currently relying on implicit fallback

**Effort:** Small

**Risk:** Low

---

### Option 2: Add explicit fallback flag

**Approach:** Add `use_default: true/false` in DSL to control fallback behavior.

**Pros:**
- Explicit API semantics
- Backward-compatibility path possible

**Cons:**
- API surface expansion
- More docs/tests required

**Effort:** Medium

**Risk:** Medium

## Recommended Action


## Technical Details

**Affected files:**
- `lib/ruby_llm/skills/agent_extensions.rb`
- `lib/ruby_llm/skills/chat_extensions.rb`
- `test/ruby_llm/skills/test_agent_extensions.rb`

## Resources

- PR: https://github.com/kieranklaassen/ruby_llm-skills/pull/2
- Reproduction command output from review session (`skills { nil }` -> `valid-skill` visible)

## Acceptance Criteria

- [x] `skills { nil }` does not register any `:skill` tool
- [x] `skills { [] }` does not register any `:skill` tool
- [x] Existing explicit `skills "path"` behavior remains unchanged
- [x] Regression tests added for nil/empty dynamic sources

## Work Log

### 2026-02-17 - Code Review Finding

**By:** Codex

**Actions:**
- Confirmed behavior via direct runtime reproduction
- Correlated with parallel reviewer findings

**Learnings:**
- Empty dynamic sources currently map to implicit default-path behavior

### 2026-02-17 - Resolution

**By:** Codex

**Actions:**
- Updated `AgentExtensions#apply_skills` to normalize and short-circuit empty sources
- Added regression tests for `skills { nil }` and `skills { [] }` behavior
- Verified explicit source behavior remains unchanged

**Learnings:**
- Empty dynamic sources should map to "no skill tool" rather than implicit default fallback
