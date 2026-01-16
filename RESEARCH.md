# RubyLLM::Skills Research Notes

Research gathered for implementing the ruby_llm-skills gem.

## Primary Sources

### Official Anthropic Resources

- **[Agent Skills Specification](https://agentskills.io/specification)** - The official open standard for skills format, frontmatter fields, validation rules, and directory structure.

- **[Anthropic Skills Repository](https://github.com/anthropics/skills)** - Official repository with skill examples, including production document skills (docx, pdf, pptx, xlsx). 41.8k stars.

- **[Anthropic Engineering Blog: Equipping agents for the real world](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)** - Design philosophy behind skills, progressive disclosure architecture.

- **[Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)** - How skills work in Claude Code, discovery mechanisms, subagent integration.

- **[Claude Platform Skills Overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)** - API documentation, skill structure, three-level loading system, security considerations.

- **[Claude Agent SDK Python](https://github.com/anthropics/claude-agent-sdk-python)** - Python SDK patterns for tools and MCP servers.

### Technical Deep Dives

- **[Claude Skills Deep Dive by Lee Hanchung](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)** - First principles analysis of how skills work under the hood: discovery, system prompt integration, two-message injection pattern.

- **[Inside Claude Code Skills by Mikhail Shilkov](https://mikhail.io/2025/10/claude-code-skills/)** - Technical implementation details, skill tool definition structure, runtime invocation.

### RubyLLM Ecosystem

- **[RubyLLM](https://github.com/crmne/ruby_llm)** - The base gem we're extending. Unified interface for multiple LLM providers.

- **[RubyLLM::MCP](https://github.com/patvice/ruby_llm-mcp)** - MCP extension for RubyLLM. Reference for extension patterns and API design.

---

## Agent Skills Specification Summary

### SKILL.md Format

```yaml
---
name: skill-name           # Required. Max 64 chars. Lowercase + hyphens only.
description: What it does  # Required. Max 1024 chars. Include when to use it.
license: Apache-2.0        # Optional
compatibility: Claude Code # Optional. Max 500 chars.
metadata:                  # Optional. Arbitrary key-value pairs.
  author: example-org
  version: "1.0"
allowed-tools: Bash Read   # Optional. Pre-approved tools (experimental).
---

# Skill Instructions

Markdown content here...
```

### Name Field Rules

- Max 64 characters
- Lowercase letters, numbers, and hyphens only
- Must not start/end with hyphen
- No consecutive hyphens
- Must match parent directory name

### Directory Structure

```
skill-name/
├── SKILL.md           # Required
├── scripts/           # Optional - executable code
├── references/        # Optional - additional documentation
└── assets/            # Optional - templates, images, static files
```

### Progressive Disclosure (Three-Level Loading)

| Level | When Loaded | Token Cost | Content |
|-------|-------------|------------|---------|
| 1: Metadata | Always (startup) | ~100 tokens/skill | name + description from frontmatter |
| 2: Instructions | When triggered | <5k tokens | SKILL.md body |
| 3: Resources | As needed | Unlimited | scripts/, references/, assets/ |

---

## How Skills Are Injected

### System Prompt Integration

Skills metadata is embedded in the Skill tool's description as `<available_skills>`:

```xml
<available_skills>
<skill>
  <name>pdf-report</name>
  <description>Generate PDF reports...</description>
  <location>app/skills/pdf-report</location>
</skill>
</available_skills>
```

### Two-Message Injection Pattern

When a skill triggers, two user messages are created:

1. **Visible message** (`isMeta: false`): Shows "The 'pdf' skill is loading"
2. **Hidden message** (`isMeta: true`): Contains full SKILL.md instructions, sent to API but hidden from UI

### Skill Selection

Selection is purely language-model based. No embeddings or classifiers - Claude's reasoning determines which skill matches user intent based on descriptions.

---

## RubyLLM-MCP Patterns (Reference Implementation)

### Client Factory Pattern

```ruby
client = RubyLLM::MCP.client(name:, adapter:, transport_type:, config:)
```

### Chat Integration Methods

```ruby
chat.with_tools(*client.tools)
chat.with_resource(resource)
chat.with_resource_template(template, arguments: {})
chat.with_prompt(prompt, arguments: {})
```

### Collection-Based Access

```ruby
client.tools          # Array of Tool objects
client.resources      # Array of Resource objects
client.prompts        # Array of Prompt objects
client.tool(name)     # Single lookup
```

---

## Andrew Kane Gem Style Summary

### Core Philosophy

- Simplicity over cleverness
- Zero or minimal dependencies
- Explicit code over metaprogramming
- Rails integration without Rails coupling

### Entry Point Pattern

```ruby
# lib/gemname.rb

# 1. Standard library
require "forwardable"

# 2. Internal modules
require_relative "gemname/skill"
require_relative "gemname/version"

# 3. Conditional Rails (never require Rails directly)
require_relative "gemname/railtie" if defined?(Rails)

# 4. Module with config
module GemName
  class Error < StandardError; end

  class << self
    attr_accessor :default_path, :logger
  end

  self.default_path = "app/skills"
end
```

### Configuration Pattern

Use `class << self` with `attr_accessor`, not Configuration objects:

```ruby
module RubyLLM
  module Skills
    class << self
      attr_accessor :default_path, :logger
    end

    self.default_path = "app/skills"
  end
end
```

### Rails Integration

Always use `ActiveSupport.on_load`:

```ruby
# lib/ruby_llm/skills/railtie.rb
module RubyLLM
  module Skills
    class Railtie < Rails::Railtie
      initializer "ruby_llm_skills.configure" do
        ActiveSupport.on_load(:active_record) do
          # Extensions here
        end
      end
    end
  end
end
```

### Gemspec Pattern

Zero runtime dependencies when possible:

```ruby
Gem::Specification.new do |spec|
  spec.name = "ruby_llm-skills"
  spec.version = RubyLLM::Skills::VERSION
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["*.{md,txt}", "{lib}/**/*"]
  spec.require_path = "lib"
  # Dev deps go in Gemfile, not here
end
```

### Testing

Minitest only, no RSpec:

```ruby
# test/test_helper.rb
require "bundler/setup"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"
```

### Anti-Patterns to Avoid

- `method_missing` (use `define_method`)
- Configuration objects (use class accessors)
- `@@class_variables` (use `class << self`)
- Requiring Rails gems directly
- Many runtime dependencies
- Committing Gemfile.lock in gems
- RSpec (use Minitest)
- Heavy DSLs

---

## Database Storage Options

### Option A: Text Content

```ruby
create_table :skills do |t|
  t.string :name, null: false
  t.text :description, null: false
  t.text :content, null: false  # Full SKILL.md content
  t.references :user
  t.timestamps
end
```

### Option B: Binary Zip

```ruby
create_table :skills do |t|
  t.string :name, null: false
  t.text :description, null: false
  t.binary :data, null: false  # Zip file blob
  t.references :user
  t.timestamps
end
```

### Detection Logic

```ruby
def storage_format(record)
  if record.respond_to?(:content) && record.content.present?
    :text
  elsif record.respond_to?(:data) && record.data.present?
    :binary
  else
    raise Error, "Skill must have content or data"
  end
end
```

---

## Security Considerations

From Anthropic's documentation:

- Only use skills from trusted sources
- Skills can direct Claude to invoke tools in unexpected ways
- Audit all bundled files before use
- External URL fetching poses particular risk
- Treat like installing software

---

## Open Standard Adoption

As of December 2025, the Agent Skills spec is an open standard adopted by:

- Anthropic (Claude Code, Claude.ai, Claude API)
- OpenAI (Codex CLI, ChatGPT)
- Google (Gemini CLI)

Skills are model-agnostic and can be used across different AI providers.
