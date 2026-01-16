# RubyLLM::Skills

Agent Skills for [RubyLLM](https://github.com/crmne/ruby_llm). Teach your AI how to do things your way.

Skills are folders of instructions, scripts, and resources that extend LLM capabilities for specialized tasks. This gem implements the [Agent Skills specification](https://agentskills.io/specification) for RubyLLM.

[![Gem Version](https://badge.fury.io/rb/ruby_llm-skills.svg)](https://badge.fury.io/rb/ruby_llm-skills)
[![CI](https://github.com/kieranklaassen/ruby_llm-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kieranklaassen/ruby_llm-skills/actions)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "ruby_llm-skills"
```

For zip file support, also add:

```ruby
gem "rubyzip"
```

## Quick Start

```ruby
chat = RubyLLM.chat
chat.with_skills              # Load skills from app/skills
chat.ask "Create a PDF report from this data"
```

The LLM sees available skills, calls the skill tool when needed, and gets the full instructions.

## How It Works

Skills follow a three-level progressive disclosure pattern:

1. **Metadata** - Name and description embedded in tool description (~100 tokens per skill)
2. **Instructions** - Full SKILL.md returned when skill tool is called
3. **Resources** - Scripts and references listed for on-demand loading

This keeps context lean while making capabilities available.

## Configuration

```ruby
RubyLlm::Skills.default_path = "lib/skills"   # Default: app/skills
RubyLlm::Skills.logger = Rails.logger         # Default: nil
```

## Loading Skills

### From Filesystem

```ruby
# Load from default path
loader = RubyLlm::Skills.from_directory

# Load from specific directory
loader = RubyLlm::Skills.from_directory("lib/skills")

# Load a single skill
skill = RubyLlm::Skills.load("app/skills/pdf-report")
```

### From Zip Files

```ruby
loader = RubyLlm::Skills.from_zip("skills.zip")
```

Requires `rubyzip` gem.

### From Database

Store skills in your database for per-user customization:

```ruby
# Migration
create_table :skills do |t|
  t.string :name, null: false
  t.text :description, null: false
  t.text :content, null: false  # SKILL.md body content
  t.references :user
  t.timestamps
end

# Load from ActiveRecord
loader = RubyLlm::Skills.from_database(current_user.skills)
```

Records must respond to `#name`, `#description`, and `#content`.

### Combining Sources

```ruby
# Compose multiple loaders
loader = RubyLlm::Skills.compose(
  RubyLlm::Skills.from_directory("app/skills"),
  RubyLlm::Skills.from_database(current_user.skills)
)

# Earlier loaders take precedence for duplicate names
skill_tool = RubyLlm::Skills::SkillTool.new(loader)
```

## Skill Discovery

The SkillTool embeds skill metadata in its description:

```xml
<available_skills>
  <skill>
    <name>pdf-report</name>
    <description>Generate PDF reports with charts...</description>
  </skill>
  <skill>
    <name>data-analysis</name>
    <description>Analyze datasets and create visualizations...</description>
  </skill>
</available_skills>
```

When the LLM calls the skill tool with a skill name, it receives the full SKILL.md content:

```
# Skill: pdf-report

# PDF Report Generator

## Quick Start
...

## Available Scripts
- generate.rb

## Available References
- templates.md
```

## API Reference

### Chat Integration

```ruby
# Default path (app/skills)
chat.with_skills

# Single path
chat.with_skills("lib/skills")

# Multiple paths
chat.with_skills("app/skills", "app/commands")

# With database skills (auto-detected)
chat.with_skills("app/skills", user.skills)

# Rails acts_as_chat models work the same way
Chat.create!(model: "gpt-4").with_skills.ask("Help me")
```

### RubyLlm::Skills Module

```ruby
RubyLlm::Skills.default_path              # Get/set default skills directory
RubyLlm::Skills.logger                    # Get/set logger

RubyLlm::Skills.from_directory(path)      # Create FilesystemLoader
RubyLlm::Skills.from_zip(path)            # Create ZipLoader
RubyLlm::Skills.from_database(records)    # Create DatabaseLoader
RubyLlm::Skills.compose(*loaders)         # Create CompositeLoader
RubyLlm::Skills.load(path)                # Load single skill from directory
```

### Loaders

```ruby
loader.list                 # Array of all skills
loader.find("name")         # Find skill by name (nil if not found)
loader.get("name")          # Get skill by name (raises NotFoundError)
loader.exists?("name")      # Check if skill exists
loader.reload!              # Clear cached skills
```

### RubyLlm::Skills::Skill

```ruby
skill.name                  # "pdf-report"
skill.description           # "Generate PDF reports..."
skill.content               # Full SKILL.md body (lazy loaded)
skill.license               # Optional license
skill.compatibility         # Optional compatibility info
skill.custom_metadata       # Custom key-value pairs from frontmatter
skill.allowed_tools         # Array of allowed tools (experimental)

skill.scripts               # Array of script file paths
skill.references            # Array of reference file paths
skill.assets                # Array of asset file paths

skill.path                  # Skill directory path
skill.valid?                # Validates against spec
skill.errors                # Array of validation errors
skill.virtual?              # True for database skills
```

### RubyLlm::Skills::SkillTool

```ruby
require "ruby_llm/skills/skill_tool"

tool = RubyLlm::Skills::SkillTool.new(loader)

tool.name                   # "skill"
tool.description            # Dynamic description with <available_skills>
tool.parameters             # JSON Schema for parameters
tool.call({ "command" => "pdf" })   # Load skill instructions
tool.call({ "command" => "pdf", "resource" => "scripts/helper.rb" })  # Load resource
tool.to_tool_definition     # Hash for RubyLLM integration
```

## Rails Integration

Skills auto-configure via Railtie. The default path is set to `Rails.root/app/skills`.

### Generator

```bash
rails generate skill pdf-report --description "Generate PDF reports"
rails generate skill my-skill --scripts --references --assets
```

### Rake Tasks

```bash
rake skills:list              # List all skills
rake skills:validate          # Validate all skills
rake skills:show[skill-name]  # Show skill details
```

## Slash Commands

Skills can also be used as slash commands. In Claude Code, [skills and slash commands are unified](https://github.com/anthropics/claude-code/issues/17578) - both use the same Skill tool.

### Creating a Command

Commands are single-file skills in `app/commands/`:

```
app/commands/
├── write-poem.md
├── review-code.md
└── generate-tests.md
```

Each command is a markdown file with frontmatter:

```markdown
---
name: write-poem
description: Write a poem on any topic. Use when asked to write poetry or verses.
---

# Write a Poem

Write a creative poem based on the user's request.

## Guidelines

- Use vivid imagery
- Match the requested style (haiku, sonnet, free verse)
- Include a title
```

### Loading Commands

```ruby
# Load commands alongside skills
chat.with_skills("app/skills", "app/commands")
```

### Invoking Commands

In your application, detect the `/` prefix and invoke the skill:

```ruby
def handle_message(message)
  if message.start_with?("/")
    command_name = message[1..].split.first  # "/write-poem topic" -> "write-poem"
    result = skill_tool.execute(command: command_name)
    # Feed result to LLM as context
  else
    # Normal chat flow
  end
end
```

The LLM receives the command instructions and follows them.

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

````markdown
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
````

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Lowercase, hyphens only. Max 64 chars. |
| `description` | Yes | What it does AND when to use it. Max 1024 chars. |
| `license` | No | License identifier |
| `compatibility` | No | Environment requirements |
| `metadata` | No | Custom key-value pairs |
| `allowed-tools` | No | Space-separated tool names (experimental) |

### Skill Directories

```
skill-name/
├── SKILL.md           # Required - instructions
├── scripts/           # Optional - executable code
├── references/        # Optional - additional docs
└── assets/            # Optional - templates, images
```

### Name Rules

- Max 64 characters
- Lowercase letters, numbers, and hyphens only
- No leading/trailing hyphens
- No consecutive hyphens
- Must match parent directory name

### Best Practices

**Keep SKILL.md under 500 lines.** Move detailed content to `references/`.

**Write good descriptions.** Include both what the skill does AND when to use it:

```yaml
# Good
description: Extract text and tables from PDF files. Use when working with PDFs, forms, or document extraction.

# Bad
description: PDF helper.
```

**Use scripts for deterministic operations.** Scripts are listed but not loaded into context.

## Validation

```ruby
skill = loader.find("my-skill")
skill.valid?  # => true/false
skill.errors  # => ["name contains uppercase", ...]
```

Validation rules follow the [Agent Skills specification](https://agentskills.io/specification).

## Provider Support

Skills work with any RubyLLM provider. The skill metadata is injected into the tool description, so any model that supports tool use can discover and load skills.

## Development

```bash
git clone https://github.com/kieranklaassen/ruby_llm-skills.git
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

MIT License. See [LICENSE](LICENSE.txt) for details.

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)
- [RubyLLM](https://github.com/crmne/ruby_llm)
