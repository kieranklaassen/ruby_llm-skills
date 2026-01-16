# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RubyLLM::Skills is a Ruby gem that implements the [Agent Skills specification](https://agentskills.io/specification) for RubyLLM. It enables progressive disclosure of AI capabilities through a three-level pattern: metadata (~100 tokens), full instructions (SKILL.md), and on-demand resources (scripts, references, assets).

## Development Commands

### Setup
```bash
bin/setup                    # Install dependencies and prepare development environment
```

### Testing
```bash
bundle exec rake test        # Run all tests using Minitest
bundle exec rake             # Run default task: tests + linting
```

### Linting
```bash
bundle exec rake standard    # Run StandardRB linter
bundle exec standardrb --fix # Auto-fix linting issues
```

### Console
```bash
bin/console                  # Start IRB console with gem loaded
```

### Gem Tasks
```bash
bundle exec rake build       # Build gem to pkg/
bundle exec rake install     # Build and install gem locally
bundle exec rake release     # Build, tag, and push gem (requires credentials)
```

## Architecture

### Module Structure

The gem uses the `RubyLlm::Skills` namespace (note: lowercase 'llm' in module name):

```
lib/ruby_llm/
├── skills.rb           # Main module entry point
└── skills/
    └── version.rb      # Gem version constant
```

### Key Design Patterns

**Progressive Disclosure**: Skills load in three stages to minimize context usage:
1. Metadata (name + description) - loaded at startup, injected into system prompt
2. Full instructions (SKILL.md) - loaded when LLM determines skill is relevant
3. Resources (scripts, references, assets) - loaded on demand during execution

**Multi-Source Loading**: Skills can be loaded from:
- Filesystem directories (default: `app/skills`)
- Zip archives (for distribution)
- ActiveRecord models (for per-user customization)
- Multiple sources simultaneously (later sources override earlier ones)

**Storage Format Detection**: The gem auto-detects source types:
- Strings ending in `/` or valid directories → Filesystem
- Strings ending in `.zip` → Zip file
- ActiveRecord relations or object arrays → Database
- Database records detect format by field: `content` (text) vs `data` (binary/zip)

### Testing

Uses Minitest framework. Test structure:
- `test/test_helper.rb` - Test configuration and setup
- `test/ruby_llm/test_skills.rb` - Main test suite

## Code Style

- Uses **StandardRB** for linting (Ruby 3.1+ compatible)
- All files use `frozen_string_literal: true`
- Module naming: `RubyLlm` (lowercase 'llm'), not `RubyLLM`

## CI/CD

GitHub Actions workflow (`.github/workflows/main.yml`):
- Runs on: push to main, all PRs
- Ruby version: 3.4.2
- Tasks: `bundle exec rake` (runs tests + linting)

## Gemspec Notes

The gemspec currently has TODO placeholders that need completion before publishing:
- `spec.summary` - Add short description
- `spec.description` - Add longer description
- `spec.homepage` - Add gem website/repo URL
- `spec.metadata["allowed_push_host"]` - Set gem server
- `spec.metadata["source_code_uri"]` - Add repo URL
- `spec.metadata["changelog_uri"]` - Add changelog URL

## Skill Structure

Skills follow a convention-based directory structure:

```
skill-name/
├── SKILL.md           # Required: YAML frontmatter + markdown instructions
├── scripts/           # Optional: executable code
├── references/        # Optional: additional documentation
└── assets/            # Optional: templates, images
```

Required YAML frontmatter fields:
- `name` (lowercase, hyphens only, max 64 chars)
- `description` (what it does AND when to use it, max 1024 chars)

Optional frontmatter: `license`, `compatibility`, custom `metadata`

## Dependencies

Minimal dependencies by design. Only requires:
- Ruby >= 3.1.0
- Bundler (for gem development)
- Minitest (for testing)
- StandardRB (for linting)

No external runtime dependencies - intentionally lightweight.
