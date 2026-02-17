---
title: "feat: Add skills DSL to RubyLLM::Agent"
type: feat
status: active
date: 2026-02-17
---

# Add skills DSL to RubyLLM::Agent

## Overview

RubyLLM 1.12 introduces `RubyLLM::Agent` — a class-configured agent DSL with macros like `model`, `instructions`, `tools`, and `temperature`. Currently, `ruby_llm-skills` only integrates with `RubyLLM::Chat` via `ChatExtensions`. This plan adds a `skills` DSL macro to `RubyLLM::Agent` so skills work seamlessly in agent subclasses, matching the existing `tools` pattern.

## Problem Statement

Users defining agents with the new DSL have no way to declaratively add skills:

```ruby
# This works today:
chat = RubyLLM.chat.with_skills("app/skills")

# This doesn't:
class SupportAgent < RubyLLM::Agent
  skills "app/skills", only: [:faq, :troubleshooting]  # ← not available
end
```

## Proposed Solution

Add an `AgentExtensions` module that extends `RubyLLM::Agent` with:

1. **Class-level `skills` macro** — stores skill sources and options, supports blocks/lambdas for dynamic resolution (consistent with `tools` macro pattern)
2. **`apply_skills` hook** — called during `apply_configuration` via `prepend`, applies skills to the internal chat
3. **Instance-level `with_skills`** — delegates to the internal chat for programmatic usage (via `Agent.new`)

### DSL Examples

```ruby
# Static skills from a path
class SimpleAgent < RubyLLM::Agent
  model 'gpt-4.1'
  skills "app/skills"
end

# Multiple sources with filtering
class SupportAgent < RubyLLM::Agent
  model 'claude-sonnet-4-5-20250929'
  instructions "You are a support assistant."
  tools SearchDocs, LookupAccount
  skills "app/skills", only: [:faq, :troubleshooting]
  temperature 0.2
end

# Dynamic skills via block (has access to runtime context)
class WorkAssistant < RubyLLM::Agent
  inputs :workspace
  skills { [workspace.skill_collection] }
end

# Instance-level usage (via Agent.new, not .chat)
agent = SupportAgent.new
agent.with_skills("extra/skills")
agent.ask("Help me")

# .chat returns a RubyLLM::Chat which already has ChatExtensions
chat = SupportAgent.chat
chat.with_skills("extra/skills").ask("Help me")
```

> **Note:** `skills` with no arguments is a getter (returns the current config), matching the `tools` macro pattern. To load from the default path, use `skills RubyLLM::Skills.default_path` explicitly.

## Technical Approach

### Architecture

```
lib/ruby_llm/skills/
├── agent_extensions.rb    # NEW: AgentExtensions module
├── chat_extensions.rb     # EXISTING: unchanged
└── ...

lib/ruby_llm/skills.rb    # MODIFIED: require + include AgentExtensions
```

### Implementation

#### Phase 1: `AgentExtensions` Module

Create `lib/ruby_llm/skills/agent_extensions.rb`:

```ruby
# frozen_string_literal: true

module RubyLLM
  module Skills
    # Extensions for RubyLLM::Agent to enable declarative skill configuration.
    #
    # @example Static skills
    #   class MyAgent < RubyLLM::Agent
    #     skills "app/skills", only: [:greeting]
    #   end
    #
    # @example Dynamic skills
    #   class MyAgent < RubyLLM::Agent
    #     inputs :workspace
    #     skills { [workspace.skill_collection] }
    #   end
    #
    module AgentExtensions
      module ClassMethods
        def self.extended(base)
          base.instance_variable_set(:@skill_sources, nil)
          base.instance_variable_set(:@skill_only, nil)
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@skill_sources, @skill_sources&.dup)
          subclass.instance_variable_set(:@skill_only, @skill_only&.dup)
        end

        # Declare skill sources for this agent.
        #
        # Called with no arguments, returns the current config (getter).
        # Called with sources/block, sets the skill config (setter).
        #
        # @param sources [Array<String>] skill source paths
        # @param only [Array<Symbol, String>, nil] filter to specific skills
        # @return [Hash] when called as getter
        def skills(*sources, only: nil, &block)
          if sources.empty? && only.nil? && !block_given?
            return {sources: @skill_sources, only: @skill_only}
          end

          @skill_sources = block_given? ? block : sources
          @skill_only = only
        end
      end

      module InstanceMethods
        # Add skills to this agent instance at runtime.
        #
        # @param sources [Array] skill sources
        # @param only [Array<Symbol, String>, nil] filter
        # @return [self] for chaining
        def with_skills(*sources, only: nil)
          chat.with_skills(*sources, only: only)
          self
        end
      end

      module ConfigurationPatch
        private

        def apply_configuration(chat_object, **kwargs)
          super
          input_values = kwargs[:input_values] || {}
          apply_skills(llm_chat_for(chat_object),
            runtime_context(chat: chat_object, inputs: input_values))
        end

        def apply_skills(llm_chat, runtime)
          config = skills
          sources = config[:sources]
          return if sources.nil?

          resolved = sources.is_a?(Proc) ? Array(runtime.instance_exec(&sources)) : sources
          only = config[:only]

          llm_chat.with_skills(*resolved, only: only)
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
        base.singleton_class.prepend(ConfigurationPatch)
      end
    end
  end
end
```

Key design decisions:

- **`prepend` on singleton class** for `ConfigurationPatch` — hooks into `apply_configuration` without replacing it. Calls `super` first so all standard configuration (model, tools, instructions, etc.) happens, then applies skills.
- **`**kwargs` passthrough** — uses `**kwargs` instead of explicit keyword arguments for resilience against upstream signature changes in `apply_configuration`.
- **`inherited` hook** — copies `@skill_sources` and `@skill_only` to subclasses, matching how Agent copies `@tools`, `@temperature`, etc. Calls `super` to chain with Agent's own `inherited`.
- **Block support** — evaluated at runtime via the same `runtime_context` pattern Agent uses for `tools` and `params`.
- **No-arg `skills` is a getter** — matches the `tools` macro convention. Users must explicitly provide a path.
- **Instance `with_skills`** — delegates to `chat` (the `@chat` attr_reader from Agent), returns `self` for chaining. Only reachable via `Agent.new`, since `.chat` class method returns a bare `RubyLLM::Chat` (which already has `ChatExtensions`).

#### Phase 2: Wire It Up

Modify `lib/ruby_llm/skills.rb`:

```ruby
# After line 12 (require chat_extensions):
require_relative "skills/agent_extensions"

# After line 18 (Chat.include):
RubyLLM::Agent.include(RubyLLM::Skills::AgentExtensions)
```

No `if defined?` guard needed since we're bumping the dependency to >= 1.12.

#### Phase 3: Bump Dependency

In `ruby_llm-skills.gemspec`, change:

```ruby
spec.add_dependency "ruby_llm", ">= 1.12"
```

#### Phase 4: Tests

Create `test/ruby_llm/skills/test_agent_extensions.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TestAgentExtensions < Minitest::Test
  include FixturesHelper

  # --- Class-level DSL ---

  def test_skills_macro_stores_sources
    agent_class = Class.new(RubyLLM::Agent) { skills "app/skills" }
    config = agent_class.skills
    assert_equal ["app/skills"], config[:sources]
    assert_nil config[:only]
  end

  def test_skills_macro_with_only_filter
    agent_class = Class.new(RubyLLM::Agent) {
      skills "app/skills", only: [:greeting]
    }
    assert_equal [:greeting], agent_class.skills[:only]
  end

  def test_skills_macro_with_multiple_sources
    agent_class = Class.new(RubyLLM::Agent) {
      skills "app/skills", "app/commands"
    }
    assert_equal ["app/skills", "app/commands"], agent_class.skills[:sources]
  end

  def test_skills_macro_with_block
    agent_class = Class.new(RubyLLM::Agent) {
      skills { ["dynamic/path"] }
    }
    assert agent_class.skills[:sources].is_a?(Proc)
  end

  def test_skills_no_args_is_getter
    agent_class = Class.new(RubyLLM::Agent)
    config = agent_class.skills
    assert_nil config[:sources]
    assert_nil config[:only]
  end

  # --- Inheritance ---

  def test_skills_inherited_by_subclass
    parent = Class.new(RubyLLM::Agent) {
      skills "app/skills", only: [:greeting]
    }
    child = Class.new(parent)
    assert_equal ["app/skills"], child.skills[:sources]
    assert_equal [:greeting], child.skills[:only]
  end

  def test_child_can_override_parent_skills
    parent = Class.new(RubyLLM::Agent) { skills "parent/skills" }
    child = Class.new(parent) { skills "child/skills" }
    assert_equal ["child/skills"], child.skills[:sources]
    assert_equal ["parent/skills"], parent.skills[:sources]
  end

  # --- Combined with tools ---

  def test_skills_and_tools_coexist
    tool_class = Class.new(RubyLLM::Tool) do
      description "Test tool"
      def execute = "ok"
    end

    agent_class = Class.new(RubyLLM::Agent) {
      tools tool_class
      skills "app/skills"
    }

    assert_equal [tool_class], agent_class.tools
    assert_equal ["app/skills"], agent_class.skills[:sources]
  end

  # --- apply_configuration integration ---

  def test_agent_chat_registers_skill_tool
    agent_class = Class.new(RubyLLM::Agent) {
      skills fixtures_path
    }
    chat = agent_class.chat
    assert chat.tools.key?(:skill), "Expected :skill tool to be registered"
  end

  def test_agent_new_registers_skill_tool
    agent_class = Class.new(RubyLLM::Agent) {
      skills fixtures_path
    }
    agent = agent_class.new
    assert agent.chat.tools.key?(:skill)
  end

  def test_agent_without_skills_has_no_skill_tool
    agent_class = Class.new(RubyLLM::Agent)
    chat = agent_class.chat
    refute chat.tools.key?(:skill)
  end

  # --- Instance-level with_skills ---

  def test_instance_with_skills_adds_to_chat
    agent_class = Class.new(RubyLLM::Agent)
    agent = agent_class.new
    result = agent.with_skills(fixtures_path)
    assert_equal agent, result  # returns self
    assert agent.chat.tools.key?(:skill)
  end
end
```

Integration test in `test/ruby_llm/skills/test_agent_integration.rb` (VCR-recorded):

```ruby
# frozen_string_literal: true

require "integration_helper"

class TestAgentIntegration < Minitest::Test
  include FixturesHelper

  def test_agent_with_skills_can_discover_and_use_skills
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-4.1-mini"
      skills fixtures_path
    end

    VCR.use_cassette("agent_with_skills") do
      chat = agent_class.chat
      response = chat.ask("What skills do you have available?")
      assert response.content.length > 0
    end
  end
end
```

#### Phase 5: Update README / Documentation

Add Agent usage examples to README alongside existing Chat examples. Brief section:

```markdown
### With RubyLLM::Agent (v1.12+)

```ruby
class SupportAgent < RubyLLM::Agent
  model 'gpt-4.1'
  skills "app/skills", only: [:faq, :troubleshooting]
end

chat = SupportAgent.chat
chat.ask("How do I reset my password?")
```
```

## Acceptance Criteria

- [x] `skills` class macro works on `RubyLLM::Agent` subclasses (static sources, `only:` filter, block form)
- [x] `skills` no-arg is a getter (returns `{sources:, only:}`)
- [x] Skills are inherited by Agent subclasses; child can override parent
- [x] `apply_configuration` applies skills to the internal chat after standard config
- [x] Both `.chat` and `.new` entry points apply skills correctly
- [x] Skills and tools coexist without conflict
- [x] Instance-level `with_skills` works on Agent instances (via `.new`)
- [x] Block-based skills have access to runtime context (`chat`, declared `inputs`)
- [x] `ruby_llm` dependency bumped to `>= 1.12`
- [x] Unit tests for all DSL variations pass
- [x] Integration test with VCR proves end-to-end functionality
- [x] StandardRB linting passes

## Known Considerations

### SkillTool name collision with `with_tool`

`Chat#with_tool` stores tools in a hash keyed by `tool_instance.name.to_sym`. `SkillTool` always uses name `:skill`. This means:
- Calling `with_skills` twice replaces the previous SkillTool (not duplicates) — this is correct behavior.
- The class-level `skills` DSL and instance-level `with_skills` cannot stack independently — the second call replaces the first. This is acceptable; users who need multiple sources should list them all in a single `skills` call.

### Private method dependency

`ConfigurationPatch` calls `llm_chat_for` and `runtime_context` — both private methods on `RubyLLM::Agent`'s singleton class. Using `**kwargs` passthrough mitigates signature changes, but these method names could change in future versions. Pinning to `~> 1.12` would reduce this risk.

### `.chat` vs `.new` return types

`Agent.chat` returns a `RubyLLM::Chat` (not an Agent instance). `Agent.new` returns an Agent with a `chat` accessor. Both paths go through `apply_configuration`, so skills are applied in both cases. The instance-level `with_skills` on AgentExtensions is only reachable via `.new`.

## Dependencies & Risks

- **RubyLLM 1.12 must be released and installable** — the Agent class must be available. If 1.12 is not yet on RubyGems, we may need to point at a git ref temporarily.
- **`prepend` on singleton class** — cleanest way to hook into `apply_configuration`. Calls `super` so upstream changes are preserved.
- **No Rails-specific changes needed** — the Railtie already extends `ChatExtensions` onto `acts_as_chat` models. Agent integration works at the Ruby level, independent of Rails.

## References

- [RubyLLM 1.12 Agents blog post](https://paolino.me/rubyllm-1-12-agents/)
- RubyLLM Agent source: `lib/ruby_llm/agent.rb` (upstream)
- Current Chat integration: `lib/ruby_llm/skills/chat_extensions.rb`
- Current skills entry point: `lib/ruby_llm/skills.rb:18`
