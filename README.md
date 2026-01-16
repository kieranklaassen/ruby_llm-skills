# RubyLLM::Skills

Agent Skills for [RubyLLM](https://github.com/crmne/ruby_llm). Teach your AI how to do things your way.

Skills are folders of instructions, scripts, and resources that extend LLM capabilities for specialized tasks. This gem implements the [Agent Skills specification](https://agentskills.io/specification) for RubyLLM.

[![Gem Version](https://badge.fury.io/rb/ruby_llm-skills.svg)](https://badge.fury.io/rb/ruby_llm-skills)
[![Build Status](https://github.com/patvice/ruby_llm-skills/actions/workflows/build.yml/badge.svg)](https://github.com/patvice/ruby_llm-skills/actions)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "ruby_llm-skills"
```

## Quick Start

```ruby
chat = RubyLLM.chat
chat.with_skills              # Load skills from app/skills
chat.ask "Create a PDF report from this data"
```

That's it. Skills are discovered automatically and injected into the system prompt.

## How It Works

Skills follow a three-level progressive disclosure pattern:

1. **Metadata** - Name and description loaded at startup (~100 tokens per skill)
2. **Instructions** - Full SKILL.md loaded when skill triggers
3. **Resources** - Scripts and references loaded on demand

This keeps context lean while making capabilities available.

## Configuration

```ruby
RubyLLM::Skills.default_path = "lib/skills"   # Default: app/skills
RubyLLM::Skills.logger = Rails.logger         # Default: nil
```

## Loading Skills

### From Filesystem (Default)

```ruby
# Load from default path (app/skills)
chat.with_skills

# Load from specific directory
chat.with_skills(from: "lib/skills")

# Load specific skills only
chat.with_skills(only: [:pdf_report, :data_analysis])
```

### From Multiple Sources

Pass an array to load from multiple locations:

```ruby
chat.with_skills(from: [
  "app/skills",                # Directory
  "extras/skills.zip",         # Zip file
  current_user.skills          # ActiveRecord relation
])
```

Sources are loaded in order. Later skills with the same name override earlier ones.

### From Database

Store complete skills in your database for per-user customization. Two storage formats are supported:

**Option A: Store as text (SKILL.md content)**

```ruby
# Migration
create_table :skills do |t|
  t.string :name, null: false
  t.text :description, null: false
  t.text :content, null: false  # Full SKILL.md content
  t.references :user
  t.timestamps
end

# Model
class Skill < ApplicationRecord
  belongs_to :user, optional: true

  validates :name, format: { with: /\A[a-z0-9-]+\z/ }
end

# Create a skill
current_user.skills.create!(
  name: "my-workflow",
  description: "Custom workflow for data processing",
  content: <<~SKILL
    # My Workflow

    ## Steps
    1. Load the data
    2. Process with custom rules
    3. Export results
  SKILL
)
```

**Option B: Store as binary (zip file)**

For skills with scripts, references, or assets:

```ruby
# Migration
create_table :skills do |t|
  t.string :name, null: false
  t.text :description, null: false
  t.binary :data, null: false  # Zip file blob
  t.references :user
  t.timestamps
end

# Model
class Skill < ApplicationRecord
  belongs_to :user, optional: true
end

# Upload a skill zip
skill_zip = File.read("my-skill.zip")
current_user.skills.create!(
  name: "pdf-report",
  description: "Generate PDF reports with charts",
  data: skill_zip
)
```

**Loading database skills**

```ruby
# Combine app skills with user's custom skills
chat.with_skills(from: [
  "app/skills",           # Base skills from filesystem
  current_user.skills     # User's skills from database
])
```

The gem detects the storage format automatically:
- Records with `content` field → parsed as SKILL.md text
- Records with `data` field → extracted as zip

### From Zip Files

```ruby
chat.with_skills(from: "skills.zip")
chat.with_skills(from: ["core.zip", "custom.zip"])
```

### Source Detection

The gem auto-detects source type:

| Input | Type |
|-------|------|
| String ending in `/` or directory path | Filesystem |
| String ending in `.zip` | Zip file |
| ActiveRecord relation or array of objects | Database |

## Rails Integration

Skills load automatically via Railtie. No configuration needed.

```ruby
# app/skills/ is scanned at boot
# Skills available on any RubyLLM chat

class ReportsController < ApplicationController
  def create
    chat = RubyLLM.chat
    chat.with_skills  # Already has app/skills loaded
    chat.ask "Generate quarterly report from #{@data}"
  end
end
```

### Per-User Skills with ActiveRecord

```ruby
class User < ApplicationRecord
  has_many :skills
end

class Skill < ApplicationRecord
  belongs_to :user, optional: true

  validates :name, presence: true,
    format: { with: /\A[a-z0-9-]+\z/ },
    length: { maximum: 64 }
  validates :description, presence: true,
    length: { maximum: 1024 }
  validates :content, presence: true
end
```

## Skill Discovery

Skills are injected into the system prompt as available tools:

```xml
<available_skills>
<skill>
  <name>pdf-report</name>
  <description>Generate PDF reports with charts...</description>
  <location>app/skills/pdf-report</location>
</skill>
</available_skills>
```

When the LLM determines a skill is relevant, it reads the full `SKILL.md` into context.

## API Reference

### RubyLLM::Skills

```ruby
RubyLLM::Skills.default_path      # Get/set default skills directory
RubyLLM::Skills.logger            # Get/set logger
RubyLLM::Skills.load(from:)       # Load skills from path/database/zip
RubyLLM::Skills.validate(skill)   # Validate skill structure
```

### RubyLLM::Skills::Skill

```ruby
skill = RubyLLM::Skills.find("pdf-report")

skill.name                    # "pdf-report"
skill.description             # "Generate PDF reports..."
skill.content                 # Full SKILL.md content
skill.path                    # Filesystem path
skill.metadata                # Parsed frontmatter hash
skill.references              # Array of reference files
skill.scripts                 # Array of script files
skill.assets                  # Array of asset files
skill.valid?                  # Validates structure
```

### Chat Integration

```ruby
chat = RubyLLM.chat

chat.with_skills                    # Load default skills
chat.with_skills(only: [:name])     # Load specific skills
chat.with_skills(except: [:name])   # Exclude skills
chat.with_skills(from: records)     # Load from database
chat.skills                         # List loaded skills
chat.skill_metadata                 # Get metadata for prompt
```

## Validation

Validate skills match the specification:

```ruby
skill = RubyLLM::Skills.find("my-skill")
skill.valid?  # => true/false
skill.errors  # => ["name contains uppercase"]

# Validate all skills
RubyLLM::Skills.validate_all
# => { valid: [...], invalid: [...] }
```

## Provider Support

Skills work with any RubyLLM provider. The skill metadata is injected into the system prompt, so any model that supports system prompts can use skills.

Tested with: OpenAI, Anthropic, Google Gemini, AWS Bedrock, Ollama.

## Comparison with MCP

| Feature | Skills | MCP |
|---------|--------|-----|
| Execution | Prompt-based | Tool-based |
| Setup | Drop in folder | Server config |
| Context | Progressive disclosure | Always available |
| Best for | Domain knowledge | External integrations |

Use skills for specialized instructions. Use [ruby_llm-mcp](https://github.com/patvice/ruby_llm-mcp) for external tool integrations. They compose well together.

## Creating Skills

Create a folder with a `SKILL.md` file:

```
app/skills/
└── pdf-report/
    ├── SKILL.md
    ├── scripts/
    │   └── generate.rb
    └── references/
        └── templates.md
```

The `SKILL.md` requires YAML frontmatter:

```yaml
---
name: pdf-report
description: Generate PDF reports with charts and tables. Use when asked to create reports, export data to PDF, or generate printable documents.
---

# PDF Report Generator

## Quick Start

Use the bundled script for generation:

```bash
ruby scripts/generate.rb --input data.json --output report.pdf
```

## Guidelines

- Always include page numbers
- Use company logo from assets/
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Lowercase, hyphens only. Max 64 chars. |
| `description` | Yes | What it does AND when to use it. Max 1024 chars. |
| `license` | No | License identifier |
| `compatibility` | No | Environment requirements |
| `metadata` | No | Custom key-value pairs |

### Skill Directories

```
skill-name/
├── SKILL.md           # Required - instructions
├── scripts/           # Optional - executable code
├── references/        # Optional - additional docs
└── assets/            # Optional - templates, images
```

### Best Practices

**Keep SKILL.md under 500 lines.** Move detailed content to `references/`.

**Write good descriptions.** Include both what the skill does AND when to use it:

```yaml
# Good
description: Extract text and tables from PDF files. Use when working with PDFs, forms, or document extraction.

# Bad
description: PDF helper.
```

**Use scripts for deterministic operations.** Scripts execute without loading into context.

**One level of references.** Avoid deeply nested file chains.

## Development

```bash
git clone https://github.com/patvice/ruby_llm-skills.git
cd ruby_llm-skills
bundle install
bundle exec rake test
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Create a Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)
- [RubyLLM](https://github.com/crmne/ruby_llm)
- [RubyLLM::MCP](https://github.com/patvice/ruby_llm-mcp)
