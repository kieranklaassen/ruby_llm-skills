# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestBundle < Minitest::Test
  include MarketplaceTestHelper

  Bundle = RubyLLM::Skills::Marketplace::Bundle
  Manifest = RubyLLM::Skills::Marketplace::Manifest
  InvalidPluginError = RubyLLM::Skills::Marketplace::InvalidPluginError

  def writing_files
    plugin_fixture_files("basic", "plugins/writing")
  end

  def writing_entry
    Manifest.discover(marketplace_fixture_files("basic")).plugin("writing")
  end

  def bundle
    @bundle ||= Bundle.new(writing_files, entry: writing_entry)
  end

  def test_name_and_manifest_come_from_plugin_json_merged_with_the_entry
    assert_equal "writing", bundle.name
    assert_equal ".claude-plugin/plugin.json", bundle.manifest_path
    assert_equal "1.2.0", bundle.manifest_version
    assert_equal "1.2.0", bundle.version
    assert_equal "manifest", bundle.version_kind
    assert_equal "Drafting skills, a help command and a reviewer agent.", bundle.description
    assert_equal "writing", bundle.manifest["category"]
  end

  def test_directory_skills_are_kept_under_their_name
    assert_includes bundle.tree.keys, "skills/draft/SKILL.md"
    assert_includes bundle.tree.keys, "skills/draft/references/local.md"
    draft = bundle.skills.find { |skill| skill.name == "draft" }
    assert_equal "skill", draft.kind
    assert_equal "skills/draft", draft.path
    assert_equal "skills/draft", draft.tree_path
  end

  def test_commands_become_single_file_skills_named_after_the_file
    assert_equal %w[draft help nested-deep], bundle.skill_names
    help = bundle.tree.fetch("skills/help.md")
    assert_match(/\A---\n.*name: help\n.*---\n/m, help)
    assert_includes help, "# Help"
    assert_includes bundle.tree.keys, "skills/nested-deep.md"
    assert_equal [{"name" => "nodesc", "path" => "commands/nodesc.md", "reason" => "missing_description"}], bundle.unsupported
  end

  def test_agents_are_kept_verbatim
    assert_equal ["agents/review/reviewer.md"], bundle.agents
    assert_equal writing_files["agents/review/reviewer.md"], bundle.tree["agents/review/reviewer.md"]
  end

  def test_plugin_level_references_are_relocated_and_rewritten
    skill_md = bundle.tree.fetch("skills/draft/SKILL.md")
    assert_includes skill_md, "`.plugin/references/contract.md`"
    assert_includes skill_md, "`.plugin/defaults/`"
    assert_includes skill_md, "`references/local.md`"
    assert_includes skill_md, "`../../missing/nothing.md`"
    assert_equal writing_files["references/contract.md"], bundle.tree["skills/draft/.plugin/references/contract.md"]
    assert_equal writing_files["defaults/DEFAULTS.md"], bundle.tree["skills/draft/.plugin/defaults/DEFAULTS.md"]
    assert_equal [{"skill" => "draft", "reference" => "missing/nothing.md"}], bundle.unresolved_references
  end

  def test_everything_else_is_dropped
    dropped = bundle.dropped
    assert_includes dropped, "hooks/hooks.json"
    assert_includes dropped, "bin/run.sh"
    assert_includes dropped, ".mcp.json"
    assert_includes dropped, "README.md"
    assert_includes dropped, "commands/nodesc.md"
    refute bundle.tree.keys.any? { |path| path.start_with?("hooks/", "bin/") }
  end

  def test_tree_sha256_is_stable
    assert_equal bundle.tree_sha256, Bundle.new(writing_files, entry: writing_entry).tree_sha256
    assert_equal RubyLLM::Skills::Marketplace::Tarball.tree_sha256(bundle.tree), bundle.tree_sha256
  end

  def test_write_replaces_the_target_directory
    Dir.mktmpdir do |dir|
      target = File.join(dir, "writing")
      FileUtils.mkdir_p(target)
      File.write(File.join(target, "stale.txt"), "old")
      bundle.write!(target)
      refute File.exist?(File.join(target, "stale.txt"))
      assert File.file?(File.join(target, "skills", "draft", "SKILL.md"))
      loader = RubyLLM::Skills.from_directory(File.join(target, "skills"))
      assert_equal %w[draft help nested-deep], loader.list.map(&:name).sort
      assert loader.list.all?(&:valid?)
    end
  end

  def test_a_plugin_without_manifest_takes_the_entry_name_and_no_version
    entry = Manifest.discover(marketplace_fixture_files("basic")).plugin("notes")
    plugin = Bundle.new(plugin_fixture_files("basic", "plugins/notes"), entry: entry)
    assert_equal "notes", plugin.name
    assert_nil plugin.manifest_path
    assert_nil plugin.version
    assert_nil plugin.version_kind
    assert_equal ["note-taking"], plugin.skill_names
  end

  def test_entry_version_is_used_when_the_manifest_has_none
    entry = Manifest.parse({"name" => "m", "plugins" => [{"name" => "notes", "version" => "4.5.6", "source" => "./notes"}]}).plugin("notes")
    plugin = Bundle.new(plugin_fixture_files("basic", "plugins/notes"), entry: entry)
    assert_equal "4.5.6", plugin.version
    assert_equal "entry", plugin.version_kind
  end

  def test_strict_false_entries_are_their_own_manifest
    entry = Manifest.parse({"name" => "m", "plugins" => [{"name" => "loose", "version" => "9.9.9", "description" => "Loose.", "strict" => false, "source" => "./x"}]}).plugin("loose")
    plugin = Bundle.new(plugin_fixture_files("basic", "plugins/notes"), entry: entry)
    assert_equal "loose", plugin.name
    assert_equal "9.9.9", plugin.version
    assert_equal "entry", plugin.version_kind
    assert_equal "Loose.", plugin.description
  end

  def test_root_skill_md_becomes_one_skill_named_after_the_plugin
    files = {"SKILL.md" => "---\nname: solo\ndescription: One skill at the plugin root.\n---\n# Solo\n", "references/a.md" => "a", "other.txt" => "x"}
    plugin = Bundle.new(files, plugin_name: "solo")
    assert_equal ["solo"], plugin.skill_names
    assert_includes plugin.tree.keys, "skills/solo/SKILL.md"
    assert_includes plugin.tree.keys, "skills/solo/references/a.md"
    assert_equal ["other.txt"], plugin.dropped
  end

  def test_manifest_skill_and_command_paths_are_honored
    files = {
      ".claude-plugin/plugin.json" => JSON.generate("name" => "custom", "skills" => ["./extra/one"], "commands" => "./cmds"),
      "extra/one/SKILL.md" => "---\nname: one\ndescription: Custom skill location.\n---\n",
      "cmds/go.md" => "---\ndescription: Custom command location.\n---\nGo.\n",
      "commands/ignored.md" => "---\ndescription: Not in the manifest's commands path.\n---\n"
    }
    plugin = Bundle.new(files)
    assert_equal %w[one go], plugin.skill_names
    assert_includes plugin.dropped, "commands/ignored.md"
  end

  def test_frontmatter_name_must_match_the_directory
    files = plugin_fixture_files("broken", "mismatch")
    error = assert_raises(InvalidPluginError) { Bundle.new(files, plugin_name: "mismatch") }
    assert_includes error.message, "\"bar\""
    assert_includes error.message, "\"foo\""
  end

  def test_directory_match_ignores_case_and_underscores
    files = {"skills/My_Skill/SKILL.md" => "---\nname: my-skill\ndescription: Case-insensitive match.\n---\n"}
    assert_equal ["my-skill"], Bundle.new(files, plugin_name: "p").skill_names
  end

  def test_skill_validation_errors
    missing = {"skills/a/SKILL.md" => "---\nname: a\n---\n"}
    assert_includes assert_raises(InvalidPluginError) { Bundle.new(missing, plugin_name: "p") }.message, "description is required"

    bad_name = {"skills/Bad_Name/SKILL.md" => "---\nname: Bad_Name\ndescription: x\n---\n"}
    assert_includes assert_raises(InvalidPluginError) { Bundle.new(bad_name, plugin_name: "p") }.message, "lowercase"

    no_frontmatter = {"skills/a/SKILL.md" => "# no frontmatter\n"}
    assert_includes assert_raises(InvalidPluginError) { Bundle.new(no_frontmatter, plugin_name: "p") }.message, "missing YAML frontmatter"

    bad_yaml = {"skills/a/SKILL.md" => "---\nname: [\ndescription: x\n---\n"}
    assert_includes assert_raises(InvalidPluginError) { Bundle.new(bad_yaml, plugin_name: "p") }.message, "invalid YAML"
  end

  def test_duplicate_skill_names_are_refused
    files = {
      "skills/help/SKILL.md" => "---\nname: help\ndescription: A skill named help.\n---\n",
      "commands/help.md" => "---\ndescription: A command named help.\n---\n"
    }
    error = assert_raises(InvalidPluginError) { Bundle.new(files, plugin_name: "p") }
    assert_includes error.message, "duplicate skill names"
  end

  def test_the_skill_cap_is_enforced
    RubyLLM::Skills::Marketplace.config.max_skills = 1
    assert_raises(InvalidPluginError) { Bundle.new(writing_files, entry: writing_entry) }
  end

  def test_plugin_name_is_required_and_kebab_case
    assert_raises(InvalidPluginError) { Bundle.new({"README.md" => "x"}) }
    assert_raises(InvalidPluginError) { Bundle.new({"README.md" => "x"}, plugin_name: "Not Kebab") }
  end

  def test_manifest_must_be_json_and_may_be_the_agent_plugins_root_file
    assert_raises(InvalidPluginError) { Bundle.new({".claude-plugin/plugin.json" => "nope"}, plugin_name: "p") }
    root = {"plugin.json" => JSON.generate("$schema" => "https://agent-plugins.org/schemas/plugin.json", "name" => "portable", "version" => "0.0.1")}
    plugin = Bundle.new(root)
    assert_equal "portable", plugin.name
    assert_equal "plugin.json", plugin.manifest_path
    assert_equal "0.0.1", plugin.version
  end
end
