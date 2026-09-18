# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestManifest < Minitest::Test
  include MarketplaceTestHelper

  Manifest = RubyLLM::Skills::Marketplace::Manifest
  InvalidManifestError = RubyLLM::Skills::Marketplace::InvalidManifestError

  def test_discover_reads_the_claude_shape
    catalog = Manifest.discover(marketplace_fixture_files("basic"))
    assert_equal "basic", catalog.name
    assert_equal "claude", catalog.shape
    assert_equal ".claude-plugin/marketplace.json", catalog.path
    assert_equal "Fixture Owner", catalog.owner["name"]
    assert_equal "0.1.0", catalog.version
    assert_equal "plugins", catalog.plugin_root
    assert_equal %w[writing notes], catalog.plugins.map(&:name)
  end

  def test_plugin_root_prefixes_bare_relative_sources_only
    catalog = Manifest.discover(marketplace_fixture_files("basic"))
    assert_equal "plugins/writing", catalog.plugin("writing").source.path
    explicit = Manifest.parse({"name" => "m", "metadata" => {"pluginRoot" => "./plugins"}, "plugins" => [{"name" => "x", "source" => "./x"}]})
    assert_equal "x", explicit.plugin("x").source.path
  end

  def test_discover_reads_the_codex_shape
    catalog = Manifest.discover(marketplace_fixture_files("codex"))
    assert_equal "codex", catalog.shape
    assert_equal "Codex Market", catalog.display_name
    source = catalog.plugin("tools").source
    assert_equal "relative", source.kind
    assert_equal "tools", source.path
  end

  def test_discover_reads_the_cursor_shape
    catalog = Manifest.discover(marketplace_fixture_files("cursor"))
    assert_equal "cursor", catalog.shape
    assert_equal "2.0.0", catalog.version
    entry = catalog.plugin("cur")
    assert_equal "0.3.0", entry.version
    assert_equal "cur", entry.source.path
  end

  def test_discover_prefers_the_claude_file_when_several_exist
    files = marketplace_fixture_files("basic").merge(marketplace_fixture_files("codex"))
    assert_equal "basic", Manifest.discover(files).name
  end

  def test_discover_raises_without_a_marketplace_file
    error = assert_raises(InvalidManifestError) { Manifest.discover({"README.md" => "x"}) }
    assert_includes error.message, ".claude-plugin/marketplace.json"
  end

  def test_mixed_sources_normalize_with_reasons
    catalog = Manifest.discover(marketplace_fixture_files("mixed"))
    by_name = catalog.plugins.to_h { |entry| [entry.name, entry.source] }

    assert_equal "unsupported", by_name["npm-thing"].kind
    assert_equal "npm_source", by_name["npm-thing"].reason

    assert_equal "github", by_name["remote"].kind
    assert_equal "acme/remote", by_name["remote"].repo
    assert_equal "main", by_name["remote"].ref

    assert_equal "0123456789abcdef0123456789abcdef01234567", by_name["pinned"].sha
    assert_equal "invalid_sha", by_name["badsha"].reason

    assert_equal "archive", by_name["tarball"].kind
    assert_equal "https://example.com/plugins/tarball.tar.gz", by_name["tarball"].url
    assert_equal "zip_archive", by_name["zipped"].reason
    assert_equal "unsupported_host", by_name["elsewhere"].reason

    assert_equal "gitlab", by_name["loose"].kind
    assert_equal "acme/group/loose", by_name["loose"].repo
    refute catalog.plugin("loose").strict?
    refute catalog.plugin("npm-thing").supported?
    assert catalog.plugin("remote").supported?
  end

  def test_git_url_forms
    assert_equal "github", Manifest.git_url("https://github.com/acme/repo.git").kind
    assert_equal "acme/repo", Manifest.git_url("git@github.com:acme/repo.git").repo
    assert_equal "acme/repo", Manifest.git_url("acme/repo").repo
    assert_equal "plugins/x", Manifest.git_url("https://github.com/acme/repo", subdir: "./plugins/x/").path
    assert_equal "unsafe_path", Manifest.git_url("https://github.com/acme/repo", subdir: "../x").reason
    assert_equal "invalid_url", Manifest.git_url("not a url").reason
  end

  def test_archive_validation
    assert_equal "invalid_sha256", Manifest.archive("https://example.com/a.tgz", sha256: "short").reason
    assert_equal "a" * 64, Manifest.archive("https://example.com/a.tgz", sha256: "A" * 64).sha256
    assert_equal "invalid_url", Manifest.archive("http://example.com/a.tgz").reason
  end

  def test_parse_rejects_malformed_files
    assert_raises(InvalidManifestError) { Manifest.parse("not json") }
    assert_raises(InvalidManifestError) { Manifest.parse("[]") }
    assert_raises(InvalidManifestError) { Manifest.parse({"plugins" => []}) }
    assert_raises(InvalidManifestError) { Manifest.parse({"name" => "Has Spaces", "plugins" => []}) }
    assert_raises(InvalidManifestError) { Manifest.parse({"name" => "m"}) }
    assert_raises(InvalidManifestError) { Manifest.parse({"name" => "m", "plugins" => [{"source" => "./x"}]}) }
    assert_raises(InvalidManifestError) { Manifest.parse({"name" => "m", "plugins" => [{"name" => "x", "source" => "./x"}, {"name" => "x", "source" => "./y"}]}) }
    assert_raises(InvalidManifestError) { Manifest.parse("{}" * (Manifest::MAX_BYTES / 2 + 1)) }
  end

  def test_renames_keep_well_formed_names_only
    catalog = Manifest.parse({"name" => "m", "plugins" => [], "renames" => {"old-name" => "new-name", "gone" => nil, "Bad Name" => "x", "y" => "Bad Name"}})
    assert_equal({"old-name" => "new-name", "gone" => nil}, catalog.renames)
    assert_equal({}, Manifest.parse({"name" => "m", "plugins" => []}).renames)
    assert_equal({}, Manifest.parse({"name" => "m", "plugins" => [], "renames" => ["nope"]}).renames)
  end

  def test_plugin_source_round_trips_through_hashes
    source = Manifest.github("acme/repo", ref: "dev", subdir: "p")
    assert_equal source, Manifest::PluginSource.from_h(source.to_h)
    assert_equal({"kind" => "relative", "path" => ""}, Manifest.relative("./").to_h)
  end

  def test_normalize_relative
    assert_equal "", Manifest.normalize_relative("./", allow_blank: true)
    assert_nil Manifest.normalize_relative(".", allow_blank: false)
    assert_equal "a/b", Manifest.normalize_relative("./a/./b/", allow_blank: true)
    assert_nil Manifest.normalize_relative("../a", allow_blank: true)
    assert_nil Manifest.normalize_relative("/abs", allow_blank: true)
  end
end
