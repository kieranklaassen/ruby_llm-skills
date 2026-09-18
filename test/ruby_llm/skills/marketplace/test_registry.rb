# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestRegistry < Minitest::Test
  include MarketplaceTestHelper

  Registry = RubyLLM::Skills::Marketplace::Registry
  Tarball = RubyLLM::Skills::Marketplace::Tarball

  def test_add_records_a_directory_marketplace_and_caches_its_file
    record = registry.add(marketplace_fixture_path("basic"))
    assert_equal "basic", record.name
    assert_equal "directory", record.kind
    assert_equal marketplace_fixture_path("basic"), record.locator
    assert_equal Tarball.tree_sha256(marketplace_fixture_files("basic")), record.commit
    assert_equal [], record.plugin_names
    assert File.file?(File.join(scratch_root, "basic", ".claude-plugin", "marketplace.json"))

    lock = lockfile_json
    assert_equal 1, lock["version"]
    assert_equal({"kind" => "directory", "locator" => marketplace_fixture_path("basic"), "commit" => record.commit, "plugins" => {}}, lock["marketplaces"]["basic"])
  end

  def test_add_uses_as_for_the_name_and_refuses_a_clash
    registry.add(marketplace_fixture_path("basic"), as: "mine")
    assert_equal ["mine"], registry.list.map(&:name)
    registry.add(marketplace_fixture_path("basic"), as: "mine")
    error = assert_raises(ArgumentError) { registry.add(marketplace_fixture_path("codex"), as: "mine") }
    assert_includes error.message, "already added"
    assert_raises(ArgumentError) { registry.add(marketplace_fixture_path("basic"), as: "Not Valid") }
  end

  def test_add_raises_for_a_folder_without_a_marketplace_file
    assert_raises(RubyLLM::Skills::Marketplace::InvalidManifestError) { registry.add(fixtures_path) }
    assert_equal [], registry.list
  end

  def test_plugins_reads_the_cached_marketplace_file
    registry.add(marketplace_fixture_path("mixed"))
    entries = registry.plugins("mixed")
    assert_equal %w[npm-thing remote pinned badsha tarball zipped elsewhere loose], entries.map(&:name)
    refute entries.first.supported?
    assert_equal "npm_source", entries.first.source.reason
    assert_raises(RubyLLM::Skills::NotFoundError) { registry.plugins("nope") }
  end

  def test_install_installs_every_supported_plugin
    registry.add(marketplace_fixture_path("basic"))
    result = registry.install("basic")
    assert result.success?
    assert_equal %w[basic/notes basic/writing], result.installed.sort
    assert_equal [], result.updated
    assert_equal({}, result.skipped)

    assert_equal %w[agents/review/reviewer.md skills/draft/.plugin/defaults/DEFAULTS.md skills/draft/.plugin/references/contract.md skills/draft/SKILL.md skills/draft/references/local.md skills/help.md skills/nested-deep.md],
      installed_files("basic", "writing")
    assert_equal ["skills/note-taking/SKILL.md"], installed_files("basic", "notes")

    writing = lockfile_json["marketplaces"]["basic"]["plugins"]["writing"]
    assert_equal "1.2.0", writing["version"]
    assert_equal "manifest", writing["version_kind"]
    assert_equal registry.find("basic").commit, writing["commit"]
    assert_equal({"kind" => "relative", "path" => "plugins/writing"}, writing["source"])
    assert_equal %w[draft help nested-deep], writing["skills"]
    assert_equal Tarball.tree_sha256(Tarball.from_directory(File.join(scratch_root, "basic", "writing"))), writing["tree_sha256"]

    notes = lockfile_json["marketplaces"]["basic"]["plugins"]["notes"]
    assert_equal notes["commit"], notes["version"]
    assert_equal "commit", notes["version_kind"]
  end

  def test_install_only_selected_plugins_and_unknown_names_raise
    registry.add(marketplace_fixture_path("basic"))
    result = registry.install("basic", only: ["notes"])
    assert_equal ["basic/notes"], result.installed
    assert_equal ["notes"], registry.find("basic").plugin_names
    refute File.directory?(File.join(scratch_root, "basic", "writing"))

    error = assert_raises(RubyLLM::Skills::NotFoundError) { registry.install("basic", only: %w[writing nope]) }
    assert_includes error.message, "nope"
    refute File.directory?(File.join(scratch_root, "basic", "writing"))
    assert_raises(RubyLLM::Skills::NotFoundError) { registry.install("missing") }
  end

  def test_install_skips_unsupported_sources_with_a_reason
    registry.add(marketplace_fixture_path("mixed"))
    result = registry.install("mixed", only: ["npm-thing"])
    assert result.success?
    assert_equal({"mixed/npm-thing" => "unsupported source (npm_source)"}, result.skipped)
    assert_equal [], registry.installed
  end

  def test_install_collects_plugin_errors_and_leaves_no_tree
    registry.add(marketplace_fixture_path("broken"))
    result = registry.install("broken")
    refute result.success?
    assert_includes result.errors["broken/mismatch"], "does not match"
    refute File.exist?(File.join(scratch_root, "broken", "mismatch"))
    assert_equal({}, lockfile_json["marketplaces"]["broken"]["plugins"])
    assert_empty Dir.glob(File.join(scratch_root, "broken", ".building-*"))
  end

  def test_installed_and_loader
    registry.add(marketplace_fixture_path("basic"))
    registry.add(marketplace_fixture_path("codex"))
    registry.install("basic")
    registry.install("codex-market")

    installed = registry.installed
    assert_equal %w[basic/notes basic/writing codex-market/tools], installed.map(&:to_s)
    assert_equal File.join(scratch_root, "basic", "writing", "skills"), installed[1].skills_path

    names = registry.loader.list.map(&:name)
    assert_equal %w[draft help nested-deep note-taking tool-a], names.sort
    assert registry.loader.list.all?(&:valid?)
    assert_equal "draft", registry.loader.find("draft").name
    assert_includes registry.loader.find("draft").content, ".plugin/references/contract.md"

    facade = RubyLLM::Skills.from_marketplaces(root: scratch_root, lockfile: scratch_lockfile)
    assert_equal names.sort, facade.list.map(&:name).sort
  end

  def test_loader_over_one_plugin_is_a_plain_filesystem_loader
    registry.add(marketplace_fixture_path("codex"))
    registry.install("codex-market")
    assert_instance_of RubyLLM::Skills::FilesystemLoader, registry.loader
    assert_instance_of RubyLLM::Skills::CompositeLoader, Registry.new(root: scratch_root, lockfile: File.join(@tmpdir, "empty.json")).loader
  end

  def test_update_is_a_no_op_until_the_upstream_changes
    upstream = copy_marketplace_fixture("basic")
    registry.add(upstream)
    registry.install("basic")
    before_lock = File.read(scratch_lockfile)
    skill_md = File.join(scratch_root, "basic", "notes", "skills", "note-taking", "SKILL.md")
    before_mtime = File.mtime(skill_md)

    result = registry.update
    assert_equal %w[basic/notes basic/writing], result.unchanged.sort
    assert_equal [], result.changed
    assert_equal before_lock, File.read(scratch_lockfile)
    assert_equal before_mtime, File.mtime(skill_md)

    File.write(File.join(upstream, "plugins", "notes", "skills", "note-taking", "SKILL.md"), "---\nname: note-taking\ndescription: Changed upstream.\n---\n# New\n")
    result = registry.update("basic")
    assert_equal ["basic/notes"], result.updated
    assert_equal ["basic/writing"], result.unchanged
    assert_includes File.read(skill_md), "Changed upstream"
    lock = lockfile_json["marketplaces"]["basic"]
    assert_equal Tarball.tree_sha256(Tarball.from_directory(upstream)), lock["commit"]
    assert_equal lock["commit"], lock["plugins"]["notes"]["commit"]
    assert_equal lock["commit"], lock["plugins"]["writing"]["commit"]
  end

  def test_update_re_reads_the_marketplace_file_and_reports_removed_plugins
    upstream = copy_marketplace_fixture("basic")
    registry.add(upstream)
    registry.install("basic")

    manifest = JSON.parse(File.read(File.join(upstream, ".claude-plugin", "marketplace.json")))
    manifest["plugins"].reject! { |entry| entry["name"] == "notes" }
    File.write(File.join(upstream, ".claude-plugin", "marketplace.json"), JSON.generate(manifest))

    result = registry.update
    assert_equal({"basic/notes" => "no longer listed by the marketplace"}, result.errors)
    assert_equal ["writing"], registry.plugins("basic").map(&:name)
    assert File.directory?(File.join(scratch_root, "basic", "notes"))
  end

  def test_install_with_no_arguments_reproduces_the_lockfile
    registry.add(marketplace_fixture_path("basic"))
    registry.install("basic")
    lock_before = lockfile_json
    FileUtils.rm_rf(scratch_root)

    result = Registry.new(root: scratch_root, lockfile: scratch_lockfile).install
    assert_equal %w[basic/notes basic/writing], result.installed.sort
    assert_equal lock_before, lockfile_json
    assert_equal lock_before["marketplaces"]["basic"]["plugins"]["writing"]["tree_sha256"],
      Tarball.tree_sha256(Tarball.from_directory(File.join(scratch_root, "basic", "writing")))
  end

  def test_install_rewrites_a_tree_that_drifted_on_disk
    registry.add(marketplace_fixture_path("basic"))
    registry.install("basic")
    skill_md = File.join(scratch_root, "basic", "notes", "skills", "note-taking", "SKILL.md")
    File.write(skill_md, "tampered")

    result = registry.install
    assert_equal ["basic/notes"], result.updated
    assert_includes File.read(skill_md), "name: note-taking"
  end

  def test_remove_and_uninstall
    registry.add(marketplace_fixture_path("basic"))
    registry.install("basic")

    removed = registry.uninstall("basic", "notes")
    assert_equal "basic/notes", removed.to_s
    refute File.directory?(File.join(scratch_root, "basic", "notes"))
    assert_equal ["writing"], registry.find("basic").plugin_names
    assert_raises(RubyLLM::Skills::NotFoundError) { registry.uninstall("basic", "notes") }

    registry.remove("basic")
    refute File.directory?(File.join(scratch_root, "basic"))
    assert_equal [], registry.list
    assert_raises(RubyLLM::Skills::NotFoundError) { registry.remove("basic") }
  end

  def test_with_skills_accepts_a_registry
    registry.add(marketplace_fixture_path("codex"))
    registry.install("codex-market")

    RubyLLM.configure { |config| config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "test-key") }
    chat = RubyLLM.chat(model: "gpt-5-nano").with_skills(File.join(fixtures_path, "skills"), registry)
    names = chat.tools.fetch(:skill).loader.list.map(&:name)
    assert_includes names, "valid-skill"
    assert_includes names, "tool-a"
  end

  def test_agent_skills_accepts_a_registry
    registry.add(marketplace_fixture_path("codex"))
    registry.install("codex-market")
    local_registry = registry
    agent_class = Class.new(RubyLLM::Agent) do
      model "gpt-5-nano"
      skills local_registry
    end
    assert_equal [local_registry], agent_class.skills[:sources]
  end

  def test_unsafe_lockfile_names_never_become_paths
    File.write(scratch_lockfile, JSON.generate("version" => 1, "marketplaces" => {".." => {"kind" => "directory", "locator" => ".", "plugins" => {}}}))
    assert_raises(RubyLLM::Skills::Marketplace::LockfileError) { registry.remove("..") }

    File.write(scratch_lockfile, JSON.generate("version" => 1, "marketplaces" => {"m" => {"kind" => "directory", "locator" => ".", "plugins" => {"../x" => {}}}}))
    assert_raises(RubyLLM::Skills::Marketplace::LockfileError) { Registry.new(root: scratch_root, lockfile: scratch_lockfile).installed }
  end

  def test_default_root_and_lockfile
    default = RubyLLM::Skills.marketplaces
    assert_equal File.expand_path("vendor/skills"), default.root
    assert_equal File.expand_path("skills.lock.json"), default.lockfile_path
    assert_includes default.inspect, "skills.lock.json"
  end
end
