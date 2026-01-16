# RubyLLM::Skills

Agent Skills for [RubyLLM](https://github.com/crmne/ruby_llm). Teach your AI how to do things your way.

[![Gem Version](https://badge.fury.io/rb/ruby_llm-skills.svg)](https://badge.fury.io/rb/ruby_llm-skills)
[![CI](https://github.com/kieranklaassen/ruby_llm-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kieranklaassen/ruby_llm-skills/actions)
[![Compound Engineered](https://img.shields.io/badge/Compound-Engineered-6366f1)](https://github.com/EveryInc/compound-engineering-plugin)

## Installation

```ruby
gem "ruby_llm-skills"
```

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
bundle exec rake test        # Unit tests (151 tests)
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
