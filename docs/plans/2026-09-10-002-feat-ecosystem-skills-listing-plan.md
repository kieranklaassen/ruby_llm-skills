---
title: Add RubyLLM Skills to Ecosystem - Plan
type: docs
date: 2026-09-10
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Add RubyLLM Skills to Ecosystem - Plan

**Target repo:** [crmne/ruby_llm](https://github.com/crmne/ruby_llm)
**Plan home:** this checkout (`kieranklaassen/ruby_llm-skills`) holds the plan only.
**Product file:** `docs/_reference/ecosystem.md`

## Goal Capsule

- **Objective:** Ship a documentation PR against `crmne/ruby_llm` that lists `RubyLLM::Skills` on the official ecosystem page (`https://rubyllm.com/ecosystem/`).
- **Authority hierarchy:** Requirements (R-IDs) govern the listing. Key Technical Decisions (KTD-IDs) govern format, placement, and shipping repo. Units carry only unit-local deltas.
- **Execution profile:** One-file docs change on a fork of `crmne/ruby_llm`. Match current `main` listing style. Open a documentation PR there. Do not change gem code in this checkout.
- **Stop conditions:** Stop if `RubyLLM::Skills` is already listed on `crmne/ruby_llm` `main`, if a competing open PR already adds it, or if a fork/PR against `crmne/ruby_llm` cannot be created.
- **Tail ownership:** The product PR is against `crmne/ruby_llm`. This checkout must not open a gem-code PR as a substitute.

---

## Product Contract

### Summary

Add `RubyLLM::Skills` to the official RubyLLM ecosystem catalog so visitors of `https://rubyllm.com/ecosystem/` can find the gem, understand what it does, and reach its repository.

### Problem Frame

`ruby_llm-skills` is a published community gem that implements Agent Skills for RubyLLM. The ecosystem page invites authors to open a docs PR, and neighboring gems (`RubyLLM::MCP`, `RubyLLM::Test`, `RubyLLM::Tribunal`, and others) already have listings. Skills is absent from `crmne/ruby_llm` `main` (`docs/_reference/ecosystem.md`) and from current search of that repo's PRs.

### Requirements

**Listing content**

- R1. The ecosystem page has a `## RubyLLM::Skills` section that names the project, links to `https://github.com/kieranklaassen/ruby_llm-skills`, and states that it adds Agent Skills so models can discover and load instructions from `SKILL.md` directories, slash-command markdown files, and database records.
- R2. The listing tells RubyLLM 1.x users to stay on `ruby_llm-skills ~> 0.3.0` and RubyLLM 2.0 users to use the published prerelease `ruby_llm-skills` `0.4.0.pre1`. It must not say `0.4+` as if that selected a stable gem.
- R3. The listing does not claim zip-archive loading, later-source override, or other capabilities that this gem's public README does not document.

**Catalog fit**

- R4. The new section uses the same compact shape as the other third-party entries on current `crmne/ruby_llm` `main` (heading, repo link in the first sentence, one or two sentences, optional version caveat). It does not restore the older Why / Key Features / Installation article form still visible on the live site.
- R5. Skills is not listed a second time under Community Projects. That section stays a contribute-your-project CTA.

**Shipping**

- R6. The change lands as a documentation PR against `crmne/ruby_llm` using that repo's pull request template, marked Documentation, with no prior issue required.

### Scope Boundaries

- No gem code, README, or version bump in `kieranklaassen/ruby_llm-skills`.
- No rewrite of other ecosystem entries.
- No new RubyLLM core Skills guide and no `{% link %}` to a page that does not exist.
- No `gem install` snippet per KTD4.

#### Deferred to Follow-Up Work

- Publish `ruby_llm-skills` 0.4 to RubyGems so the 2.0 line is the default install.
- Add a first-party Skills guide in `crmne/ruby_llm` if maintainers want a `{% link %}` target.

### Success Criteria

- A visitor of the ecosystem page (once the PR is merged and the docs site deploys) can find `RubyLLM::Skills` among the other community gems and reach this repository from that listing.

---

## Planning Contract

### Key Technical Decisions

- KTD1. **Edit `crmne/ruby_llm`, not this gem repo.** The live page is generated from `docs/_reference/ecosystem.md` in `crmne/ruby_llm`. A commit here cannot appear on rubyllm.com. Governs R1, R6.
- KTD2. **Match current `main` compact listings, not the live long-form HTML.** `https://rubyllm.com/ecosystem/` still shows older Why / Key Features / Installation articles. `main` already uses short catalog entries (see Schematist through Turbovec). Editing against the live HTML would fight the source. The "simple PR" directive is honored by this choice: one file, a few sentences, the same shape as `RubyLLM::MCP` and `RubyLLM::Test` on `main`. Governs R4.
- KTD3. **Place the section immediately after `## RubyLLM::MCP`.** Both entries extend what a chat or agent can invoke (MCP servers vs reusable SKILL.md procedures). Inserting before Community Projects would hide it among unrelated storage and tokenizer gems. Governs R1.
- KTD4. **Include the 1.x / 2.0 version split; omit install snippets and zip.** Published RubyGems stable latest is still `0.3.0` (`ruby_llm ~> 1.12`). The 2.0 line is the published prerelease `0.4.0.pre1`; a bare `0.4+` constraint will not select it. Neighboring entries such as Instrumentation already warn about 1.x vs 2.0. Zip loading is mentioned in this gem's gemspec and CLAUDE.md but is not a working public API. Governs R2, R3.

### Assumptions

- The implementer can fork `crmne/ruby_llm` (or push to an existing fork) and open a PR against `crmne/ruby_llm` `main`.
- Docs-only ecosystem PRs do not need a prior approved issue. CONTRIBUTING's "issue first" rule is for features; merged listing PRs such as [crmne/ruby_llm#752](https://github.com/crmne/ruby_llm/pull/752) used the Documentation checkbox and skipped that section.
- Site deploy lag is out of scope. Definition of Done is the merged-ready PR against source, not a live rubyllm.com refresh.

### Implementation Constraints

- Re-fetch `docs/_reference/ecosystem.md` from `crmne/ruby_llm` `main` at implementation time. Other listings may have landed.
- Do not copy claims from `CLAUDE.md` that the README does not support.
- Fill `.github/pull_request_template.md` as a documentation change: Documentation type, scope checks, skip the new-feature issue requirement, mark No API changes, disclose AI assistance.

---

## Implementation Units

### U1. Add the Skills catalog section

**Goal:** Insert a compact `RubyLLM::Skills` section into the official ecosystem catalog and open the documentation PR against `crmne/ruby_llm`.

**Requirements:** R1, R2, R3, R4, R5, R6

**Dependencies:** none

**Files:**
- `docs/_reference/ecosystem.md` (in `crmne/ruby_llm`) — modify
- `.github/pull_request_template.md` (in `crmne/ruby_llm`) — follow when opening the PR; do not edit the template

**Approach:**
1. Fork or clone `crmne/ruby_llm` from current `main`. Confirm Skills is still absent.
2. After the `## RubyLLM::MCP` section, insert a heading plus two sentences per KTD2–KTD4. Keep Community Projects unchanged per R5.
3. Open a documentation PR against `crmne/ruby_llm` using that repo's template. Do not commit gem-code changes in this checkout.

**Patterns to follow:** Compact third-party entries already on `main` (`RubyLLM::MCP`, `RubyLLM::Instrumentation`, `RubyLLM::Test`). Merged docs PRs [crmne/ruby_llm#752](https://github.com/crmne/ruby_llm/pull/752) and later catalog additions.

**Execution note:** This is documentation on another repository. Prefer reading `docs/_reference/ecosystem.md` on `crmne/ruby_llm` `main` and a visual/markdown review over adding tests in either repo.

**Test scenarios:**
- Test expectation: none — documentation listing with no runtime behavior in either repository.

**Verification:**
- `docs/_reference/ecosystem.md` on the PR branch contains exactly one `RubyLLM::Skills` heading.
- The section links to `https://github.com/kieranklaassen/ruby_llm-skills`.
- The section mentions Agent Skills discovery from `SKILL.md` directories, slash-command markdown files, and database records (R1).
- The version sentence names `~> 0.3.0` for RubyLLM 1.x and the prerelease `0.4.0.pre1` for RubyLLM 2.0, not a bare `0.4+` (R2).
- The section does not claim zip loading or later-source override (R3).
- The Community Projects section is unchanged and does not list Skills (R5).
- Neighboring entries were not rewritten.
- The opened PR is against `crmne/ruby_llm`, marked Documentation, and does not claim a new RubyLLM core feature.

---

## Verification Contract

- No test suite in `crmne/ruby_llm` or this gem covers ecosystem listings. Do not add a test file for a static markdown catalog entry.
- Completeness gate: U1's verification bullets all hold on the `crmne/ruby_llm` PR diff.
- Do not run `bundle exec rake` in this gem as proof of the listing. That suite does not observe `rubyllm.com`.

---

## Definition of Done

- U1 is complete: the section exists on a PR against `crmne/ruby_llm` `main`.
- The PR body uses the documentation checkboxes in `.github/pull_request_template.md`.
- This gem's library, tests, and README are unchanged.
- Abandoned clone/fork experiments are not left as extra commits on this gem's default branch.

---

## Sources & Research

- Live page (older long-form, do not copy): https://rubyllm.com/ecosystem/
- Current source of truth: `docs/_reference/ecosystem.md` on `crmne/ruby_llm` `main`
- This gem's public story: `README.md`, `ruby_llm-skills.gemspec`
- Contribution rules: `CONTRIBUTING.md` and `.github/pull_request_template.md` in `crmne/ruby_llm`
- Prior listing PRs: [crmne/ruby_llm#752](https://github.com/crmne/ruby_llm/pull/752) (Test), [crmne/ruby_llm#808](https://github.com/crmne/ruby_llm/pull/808) (Contract; landed before the compact rewrite)
