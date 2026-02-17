---
status: complete
priority: p2
issue_id: "005"
tags: [code-review, architecture, dependency, maintenance]
dependencies: []
---

# Agent extension depends on private APIs with open-ended dependency

The new extension prepends into `RubyLLM::Agent` private configuration internals but dependency constraint is `ruby_llm >= 1.12` with no upper bound.

## Problem Statement

Private API coupling plus open-ended version range increases risk of silent breakage when upstream internals change.

## Findings

- Uses singleton `prepend` to intercept private `apply_configuration` path.
- Calls private helpers (`runtime_context`, `llm_chat_for`) directly.
- Gemspec allows any future version above 1.12.
- Evidence references:
  - `lib/ruby_llm/skills/agent_extensions.rb:64`
  - `lib/ruby_llm/skills/agent_extensions.rb:67`
  - `lib/ruby_llm/skills/agent_extensions.rb:68`
  - `ruby_llm-skills.gemspec:34`

## Proposed Solutions

### Option 1: Constrain to tested minor range (recommended)

**Approach:** Pin to `~> 1.12` (or `< 1.13`) until compatibility is confirmed.

**Pros:**
- Prevents accidental upgrades to incompatible internals
- Aligns with private API risk profile

**Cons:**
- Requires periodic dependency bump work

**Effort:** Small

**Risk:** Low

---

### Option 2: Add runtime compatibility checks + CI matrix

**Approach:** Detect required methods/signatures at load time and raise clear errors; test against supported versions.

**Pros:**
- Better failure messaging
- Supports broader version range safely

**Cons:**
- More maintenance and CI complexity

**Effort:** Medium

**Risk:** Low

## Recommended Action


## Technical Details

**Affected files:**
- `lib/ruby_llm/skills/agent_extensions.rb`
- `ruby_llm-skills.gemspec`

## Resources

- PR: https://github.com/kieranklaassen/ruby_llm-skills/pull/2

## Acceptance Criteria

- [x] Dependency policy reflects private API coupling risk
- [x] Compatibility checks/tests exist for supported ruby_llm range
- [x] Failure mode is explicit when upstream contract changes

## Work Log

### 2026-02-17 - Code Review Finding

**By:** Codex

**Actions:**
- Mapped extension call path to upstream private methods
- Confirmed open-ended dependency declaration

**Learnings:**
- Private integration points need tighter version and compatibility controls

### 2026-02-17 - Resolution

**By:** Codex

**Actions:**
- Added required-agent-method compatibility checks during extension inclusion
- Changed gem dependency from `>= 1.12` to `~> 1.12`
- Re-ran full test and lint suites after dependency-policy update

**Learnings:**
- Private API hooks should pair with explicit version policy plus boot-time compatibility checks
