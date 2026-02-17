---
status: complete
priority: p2
issue_id: "003"
tags: [code-review, reliability, agent, ruby_llm, quality]
dependencies: []
---

# Nested/invalid skills source shapes can crash at runtime

`skills` stores sources without normalizing shape. Passing arrays/collections in common patterns can produce invalid loaders and raise `NoMethodError`.

## Problem Statement

Agent DSL should fail predictably or normalize input. Current behavior allows nested arrays/non-loader objects to flow into `SkillTool`, then crashes when tool description calls `loader.list`.

## Findings

- `skills paths` (where `paths` is an array) stores nested arrays.
- Tool building later raises `undefined method 'list' for Array`.
- Dynamic blocks returning non-loader collections can also fail similarly.
- Evidence references:
  - `lib/ruby_llm/skills/agent_extensions.rb:44`
  - `lib/ruby_llm/skills/agent_extensions.rb:82`
  - `lib/ruby_llm/skills/chat_extensions.rb:40`
  - `lib/ruby_llm/skills/skill_tool.rb:108`

## Proposed Solutions

### Option 1: Normalize sources before delegation (recommended)

**Approach:** Flatten one level and reject unsupported source types early with a clear error.

**Pros:**
- Prevents late runtime crashes
- Improves DSL ergonomics (`skills paths` works)

**Cons:**
- Needs careful handling for database collections

**Effort:** Small

**Risk:** Low

---

### Option 2: Strict validation with descriptive ArgumentError

**Approach:** Keep current shape rules but raise early unless each source is String/loader/database-compatible.

**Pros:**
- Very explicit contract
- Safer than implicit coercion

**Cons:**
- Less ergonomic for callers

**Effort:** Small

**Risk:** Low

## Recommended Action


## Technical Details

**Affected files:**
- `lib/ruby_llm/skills/agent_extensions.rb`
- `lib/ruby_llm/skills/chat_extensions.rb`
- `test/ruby_llm/skills/test_agent_extensions.rb`

## Resources

- PR: https://github.com/kieranklaassen/ruby_llm-skills/pull/2
- Reproduction command output from review session (`skills paths` crash)

## Acceptance Criteria

- [x] `skills paths` (array variable) works or fails early with clear error
- [x] Dynamic block returning unsupported object types fails with descriptive error
- [x] Regression tests cover nested arrays and invalid dynamic outputs

## Work Log

### 2026-02-17 - Code Review Finding

**By:** Codex

**Actions:**
- Reproduced `NoMethodError` with nested source arrays
- Verified failure originates in `SkillTool#build_skills_xml`

**Learnings:**
- Late failure path makes debugging harder than upfront validation

### 2026-02-17 - Resolution

**By:** Codex

**Actions:**
- Added source normalization in `skills` DSL to flatten nested source arrays safely
- Added early source validation with descriptive `ArgumentError`
- Hardened `ChatExtensions#to_loader` to reject invalid source objects immediately
- Added regression tests for array-variable sources and invalid dynamic source outputs

**Learnings:**
- Early validation produces actionable errors and avoids deep runtime crashes in tool rendering
