---
status: complete
priority: p2
issue_id: "004"
tags: [code-review, architecture, compatibility, ruby]
dependencies: []
---

# Global Module#delegate patch introduces compatibility risk

The gem entrypoint globally defines `Module#delegate` if missing. The shim supports only `to:` and alters process-wide behavior.

## Problem Statement

Patching `Module` in library load path is high-impact. Incomplete method signature can break other code expecting richer delegate semantics.

## Findings

- Shim lives in `lib/ruby_llm/skills.rb` and affects entire process.
- Direct repro: `delegate :to_s, to: :bar, prefix: true` raises `ArgumentError: unknown keyword: :prefix`.
- Evidence references:
  - `lib/ruby_llm/skills.rb:5`
  - `lib/ruby_llm/skills.rb:7`

## Proposed Solutions

### Option 1: Load canonical delegation extension (recommended)

**Approach:** Prefer requiring ActiveSupport delegation extension when available, or isolate shim behind explicit compatibility module.

**Pros:**
- Avoids custom global behavior drift
- Better compatibility with ecosystem expectations

**Cons:**
- Adds optional dependency concerns

**Effort:** Medium

**Risk:** Medium

---

### Option 2: Expand shim compatibility

**Approach:** Support full keyword signature (`prefix`, etc.) and document limitations clearly.

**Pros:**
- Keeps no-extra-dependency approach

**Cons:**
- Re-implementing framework behavior is brittle

**Effort:** Medium

**Risk:** Medium

## Recommended Action


## Technical Details

**Affected files:**
- `lib/ruby_llm/skills.rb`

## Resources

- PR: https://github.com/kieranklaassen/ruby_llm-skills/pull/2
- Reproduction command output from review session (`unknown keyword: :prefix`)

## Acceptance Criteria

- [x] Global monkey patch is removed or fully compatibility-scoped
- [x] Non-Rails environment still loads `ruby_llm` agent path successfully
- [x] Regression test/documentation for compatibility behavior exists

## Work Log

### 2026-02-17 - Code Review Finding

**By:** Codex

**Actions:**
- Verified runtime behavior of new `delegate` shim
- Confirmed incompatibility with common delegate keywords

**Learnings:**
- Small compatibility shims can create broad process-level side effects

### 2026-02-17 - Resolution

**By:** Codex

**Actions:**
- Reworked fallback `delegate` shim to support common keywords (`prefix`, `allow_nil`, `private`)
- Kept shim gated to environments where `Module#delegate` is missing
- Added delegate compatibility tests

**Learnings:**
- Compatibility shims need practical option support to avoid surprising failures in host apps
