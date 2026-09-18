# RubyLLM::Skills

Agent Skills for [RubyLLM](https://github.com/crmne/ruby_llm). Teach your AI how to do things your way.

[![Gem Version](https://badge.fury.io/rb/ruby_llm-skills.svg)](https://badge.fury.io/rb/ruby_llm-skills)
[![CI](https://github.com/kieranklaassen/ruby_llm-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kieranklaassen/ruby_llm-skills/actions)
[![Compound Engineered](https://img.shields.io/badge/Compound-Engineered-6366f1)](https://github.com/EveryInc/compound-engineering-plugin)

## Installation

```ruby
gem "ruby_llm", "2.0.0.rc3"
gem "ruby_llm-skills", "0.4.0.pre2"
```

Requires RubyLLM 2.0 (`>= 2.0.0.rc3`). If you are still on RubyLLM 1.x, stay on `ruby_llm-skills ~> 0.3.0` and follow the [RubyLLM 2.0 upgrade guide](https://rubyllm.com/next/upgrading/) before upgrading both gems together.

## Quick Start

```ruby
chat = RubyLLM.chat
chat.with_skills
chat.ask "Create a PDF report from this data"
```

The LLM discovers skills, calls the skill tool, and gets instructions.

## Usage

```ruby
chat.with_skills                              # app/skills (default)
chat.with_skills("lib/skills")                # custom path
chat.with_skills("app/skills", "app/commands") # multiple paths
chat.with_skills("app/skills", user.skills)   # with database records
```

### With RubyLLM::Agent

```ruby
class SupportAgent < RubyLLM::Agent
  model "gpt-5-nano"
  instructions "You are a support assistant."
  skills "app/skills", only: [:faq, :troubleshooting]
end

chat = SupportAgent.chat
chat.ask("How do I reset my password?")

agent = SupportAgent.new
agent.with_skills("extra/skills")
agent.ask("What can you help with?")
```

`agent.with_skills(...)` replaces the current skill tool configuration.
To combine sources, pass all sources in a single `skills`/`with_skills` call.

## Creating Skills

```
app/skills/
└── pdf-report/
    ├── SKILL.md
    ├── scripts/
    └── references/
```

SKILL.md requires frontmatter:

```markdown
---
name: pdf-report
description: Generate PDF reports. Use when asked to create reports or export to PDF.
---

# PDF Report Generator

Instructions here...
```

## Slash Commands

Single-file skills work as commands:

```
app/commands/
├── write-poem.md
└── review-code.md
```

```ruby
chat.with_skills("app/skills", "app/commands")
chat.ask "/write-poem about robots"
```

## Marketplaces

Instead of adding skills one by one, add a whole plugin marketplace. The gem reads Claude Code (`.claude-plugin/marketplace.json`), Codex (`.agents/plugins/marketplace.json`) and Cursor (`.cursor-plugin/marketplace.json`) marketplaces from a GitHub repository, a GitLab project, a hosted `marketplace.json` URL or a local directory, fetches plugins over HTTPS (never `git`), and normalizes each one into the `skills/` layout the loaders read.

```ruby
marketplaces = RubyLLM::Skills.marketplaces          # vendor/skills + skills.lock.json

marketplaces.add("EveryInc/compound-writing")         # follows the default branch
marketplaces.add("typesafe-ai/skills", ref: "v0.5.7") # pinned to a tag (or a commit sha)
marketplaces.add("https://example.com/marketplace.json")

marketplaces.plugins("compound-writing").map(&:name)  # what the marketplace lists
marketplaces.install("compound-writing")              # every supported plugin
marketplaces.install("typesafe-ai", only: ["typesafe"])

marketplaces.update                                   # move unpinned marketplaces to their ref's head
marketplaces.remove("typesafe-ai")

chat.with_skills("app/skills", marketplaces)          # a registry is a skill source
```

Plugins land in `vendor/skills/<marketplace>/<plugin>/` with their `skills/` (directory skills plus `commands/*.md` as single-file skills) and `agents/`. Plugin-level files a skill references through `../../x` or `${CLAUDE_PLUGIN_ROOT}/x` are copied under `<skill>/.plugin/` so the skill tool can serve them. Hooks, MCP and LSP configuration, executables and workflows are never installed.

`skills.lock.json` records every marketplace with its kind, locator, ref and resolved commit, and every plugin with its version (the plugin manifest's, else the entry's, else the commit), commit, tree hash, source and skill names. Commit both, and `RubyLLM::Skills.marketplaces.install` (no arguments) reproduces the same trees on another machine at the recorded commits. A marketplace added with a commit sha as `ref` never moves on `update`; a branch or tag ref does.

```ruby
RubyLLM::Skills.from_marketplaces                     # a loader over the installed plugins
RubyLLM::Skills.marketplaces(root: "lib/skills/vendor", lockfile: "lib/skills/skills.lock.json")

RubyLLM::Skills::Marketplace.configure do |config|
  config.github_token = ENV["GITHUB_TOKEN"]           # the default; lifts the API rate limit
  config.max_archive_bytes = 64 * 1024 * 1024         # per plugin archive; also max_file_bytes, max_files, max_skills
  config.url_guard = ->(uri) { ... }                  # called per hop for URLs a marketplace author supplied
end
```

`install` and `update` return a result with `installed`, `updated`, `unchanged`, `skipped` (unsupported sources, with the reason) and `errors` (per plugin); they raise only for an unknown marketplace or plugin name and for a marketplace that cannot be fetched at all.

The same operations are Rake tasks, loaded by the Railtie or with `require "ruby_llm/skills/tasks"` in a plain Rakefile:

```bash
rake skills:marketplaces:add[EveryInc/compound-writing]
rake skills:marketplaces:add[typesafe-ai/skills,v0.5.7]
rake skills:marketplaces:list
rake skills:marketplaces:plugins[compound-writing]
rake skills:marketplaces:install[compound-writing]
rake skills:marketplaces:install[compound-writing,cw-draft cw-line-edit]
rake skills:marketplaces:install          # reproduce skills.lock.json
rake skills:marketplaces:update
rake skills:marketplaces:remove[compound-writing]
```

## Database Skills

Store skills or commands in your database:

```ruby
create_table :skills do |t|
  t.string :name, null: false
  t.text :description, null: false
  t.text :content, null: false  # SKILL.md body
  t.references :user
  t.timestamps
end

chat.with_skills(user.skills)
chat.ask "/my-command args"  # works as command too
```

Records must respond to `#name`, `#description`, and `#content`. For skills with scripts/references, use filesystem skills.

## Rails

Default path auto-configured to `Rails.root/app/skills`.

```bash
rails generate skill pdf-report --description "Generate PDF reports"
```

## Development

### Setup

```bash
bin/setup
```

### Running Tests

```bash
bundle exec rake test        # Unit tests (300+ tests)
bundle exec rake test_rails  # Rails integration tests (25+ tests)
bundle exec rake test_all    # Both
bundle exec rake             # Tests + linting
```

### Dummy Rails App

A minimal Rails 8 app at `test/dummy/` tests Rails integration:

- **Filesystem skills**: `app/skills/greeting/` tests directory-based loading
- **Database skills**: `Skill` model tests ActiveRecord-based loading
- **Generator tests**: Tests for `rails generate skill`
- **Composite loading**: Tests combining filesystem + database sources

```bash
cd test/dummy
bundle exec rails test  # Run Rails tests directly
```

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [RubyLLM](https://github.com/crmne/ruby_llm)

## License

MIT
