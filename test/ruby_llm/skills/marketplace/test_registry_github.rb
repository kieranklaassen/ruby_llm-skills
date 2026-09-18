# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestRegistryGithub < Minitest::Test
  include MarketplaceTestHelper

  Registry = RubyLLM::Skills::Marketplace::Registry
  Tarball = RubyLLM::Skills::Marketplace::Tarball

  SHA1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  SHA2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  REMOTE = "cccccccccccccccccccccccccccccccccccccccc"

  def test_add_and_install_from_github
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA1)
    record = registry.add("acme/skills")
    assert_equal "github", record.kind
    assert_equal "acme/skills", record.locator
    assert_nil record.ref
    assert_equal SHA1, record.commit

    result = registry.install("basic")
    assert_equal %w[basic/notes basic/writing], result.installed.sort
    assert_requested :get, "https://codeload.github.com/acme/skills/tar.gz/#{SHA1}", times: 1
    lock = lockfile_json["marketplaces"]["basic"]
    assert_equal({"kind" => "github", "locator" => "acme/skills", "commit" => SHA1}, lock.except("plugins"))
    assert_equal SHA1, lock["plugins"]["writing"]["commit"]
    assert_equal "1.2.0", lock["plugins"]["writing"]["version"]
    assert_equal SHA1, lock["plugins"]["notes"]["version"]
  end

  def test_a_branch_ref_moves_on_update_and_a_sha_ref_does_not
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA1)
    registry.add("acme/skills", ref: "main")
    registry.install("basic")

    stub_github_marketplace("acme/skills", fixture: "cursor", sha: SHA2)
    result = registry.update
    assert_equal SHA2, registry.find("basic").commit
    assert_equal({"basic/notes" => "no longer listed by the marketplace", "basic/writing" => "no longer listed by the marketplace"}, result.errors)
    assert_equal ["cur"], registry.plugins("basic").map(&:name)

    pinned = Registry.new(root: File.join(@tmpdir, "pinned"), lockfile: File.join(@tmpdir, "pinned.json"))
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA1)
    pinned.add("acme/skills", ref: SHA1)
    assert pinned.find("basic").pinned?
    pinned.install("basic")
    stub_github_marketplace("acme/skills", fixture: "cursor", sha: SHA2)
    result = pinned.update
    assert_equal SHA1, pinned.find("basic").commit
    assert_equal %w[basic/notes basic/writing], result.unchanged.sort
  end

  def test_update_reuses_the_recorded_commit_when_the_head_is_unchanged
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA1)
    registry.add("acme/skills")
    registry.install("basic")
    WebMock.reset_executed_requests!

    result = registry.update
    assert_equal %w[basic/notes basic/writing], result.unchanged.sort
    assert_requested :get, "https://api.github.com/repos/acme/skills/commits/main", times: 1
    refute_requested :get, "https://codeload.github.com/acme/skills/tar.gz/#{SHA1}"
  end

  def test_install_reproduces_github_sourced_plugins_at_their_recorded_commit
    notes = plugin_fixture_files("basic", "plugins/notes")
    stub_github_marketplace("acme/market", fixture: "mixed", sha: SHA1)
    stub_github_marketplace("acme/remote", files: notes, sha: REMOTE, ref: "main")
    registry.add("acme/market")
    result = registry.install("mixed", only: ["remote"])
    assert_equal ["mixed/remote"], result.installed
    plugin = lockfile_json["marketplaces"]["mixed"]["plugins"]["remote"]
    assert_equal REMOTE, plugin["commit"]
    assert_equal({"kind" => "github", "path" => "", "repo" => "acme/remote", "ref" => "main"}, plugin["source"])

    FileUtils.rm_rf(scratch_root)
    stub_github_marketplace("acme/remote", files: plugin_fixture_files("codex", "tools"), sha: SHA2, ref: "main")
    stub_request(:get, "https://codeload.github.com/acme/remote/tar.gz/#{REMOTE}")
      .to_return(status: 200, body: Tarball.write(notes, root: "remote-#{REMOTE}"))
    result = Registry.new(root: scratch_root, lockfile: scratch_lockfile).install
    assert_equal ["mixed/remote"], result.installed
    assert_equal REMOTE, lockfile_json["marketplaces"]["mixed"]["plugins"]["remote"]["commit"]
    assert_equal ["skills/note-taking/SKILL.md"], installed_files("mixed", "remote")
    refute_requested :get, "https://codeload.github.com/acme/remote/tar.gz/#{SHA2}"
  end

  def test_hosted_marketplace_installs_archive_sources_and_skips_relative_ones
    files = plugin_fixture_files("basic", "plugins/notes")
    archive = Tarball.write(files, root: "notes")
    digest = Digest::SHA256.hexdigest(archive)
    body = JSON.generate(
      "name" => "hosted",
      "plugins" => [
        {"name" => "notes", "version" => "3.0.0", "source" => {"source" => "archive", "url" => "https://cdn.example.com/notes.tar.gz"}},
        {"name" => "local", "source" => "./local"}
      ]
    )
    stub_request(:get, "https://example.com/marketplace.json").to_return(status: 200, body: body)
    stub_request(:get, "https://cdn.example.com/notes.tar.gz").to_return(status: 200, body: archive)

    record = registry.add("https://example.com/marketplace.json")
    assert_equal "url", record.kind
    result = registry.install("hosted")
    assert_equal ["hosted/notes"], result.installed
    assert_equal({"hosted/local" => "relative sources are not available from a hosted marketplace.json"}, result.skipped)
    plugin = lockfile_json["marketplaces"]["hosted"]["plugins"]["notes"]
    assert_equal "3.0.0", plugin["version"]
    assert_equal "entry", plugin["version_kind"]
    assert_equal digest, plugin["commit"]

    stub_request(:get, "https://cdn.example.com/notes.tar.gz").to_return(status: 200, body: Tarball.write(files.merge("extra.md" => "x"), root: "notes"))
    FileUtils.rm_rf(scratch_root)
    result = Registry.new(root: scratch_root, lockfile: scratch_lockfile).install
    assert_includes result.errors["hosted/notes"], "does not match the lockfile"
  end

  def test_fetch_failures_surface_per_plugin
    stub_github_marketplace("acme/market", fixture: "mixed", sha: SHA1)
    stub_request(:get, "https://api.github.com/repos/acme/remote/commits/main").to_return(status: 404, body: "{}")
    registry.add("acme/market")
    result = registry.install("mixed", only: ["remote"])
    refute result.success?
    assert_includes result.errors["mixed/remote"], "HTTP 404"
    assert_equal [], registry.installed
  end
end
