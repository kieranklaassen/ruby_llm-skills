# RubyLLM::Skills

Agent Skills for [RubyLLM](https://github.com/crmne/ruby_llm). Teach your AI how to do things your way.

[![Gem Version](https://badge.fury.io/rb/ruby_llm-skills.svg)](https://badge.fury.io/rb/ruby_llm-skills)
[![CI](https://github.com/kieranklaassen/ruby_llm-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kieranklaassen/ruby_llm-skills/actions)

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

```ruby
create_table :skills do |t|
  t.string :name, null: false
  t.text :description, null: false
  t.text :content, null: false
  t.references :user
  t.timestamps
end

chat.with_skills(user.skills)
```

Records must respond to `#name`, `#description`, and `#content`.

## Rails

Default path auto-configured to `Rails.root/app/skills`.

```bash
rails generate skill pdf-report --description "Generate PDF reports"
```

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [RubyLLM](https://github.com/crmne/ruby_llm)

## License

MIT
