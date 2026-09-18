# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestFetcher < Minitest::Test
  include MarketplaceTestHelper

  Fetcher = RubyLLM::Skills::Marketplace::Fetcher
  Locator = RubyLLM::Skills::Marketplace::Locator
  Manifest = RubyLLM::Skills::Marketplace::Manifest
  Tarball = RubyLLM::Skills::Marketplace::Tarball
  FetchError = RubyLLM::Skills::Marketplace::FetchError

  SHA = "1111111111111111111111111111111111111111"
  OTHER = "2222222222222222222222222222222222222222"

  def test_for_picks_the_adapter
    assert_instance_of Fetcher::Github, Fetcher.for(Locator.parse("acme/skills"))
    assert_instance_of Fetcher::Gitlab, Fetcher.for(Locator.parse("https://gitlab.com/g/p"))
    assert_instance_of Fetcher::Url, Fetcher.for(Locator.parse("https://example.com/m.json"))
    assert_instance_of Fetcher::Directory, Fetcher.for(Locator.parse("./x"))
  end

  # --- directory ---

  def test_directory_head_is_the_tree_hash_and_moves_with_the_folder
    upstream = copy_marketplace_fixture("basic")
    fetcher = Fetcher.for(Locator.parse(upstream))
    head = fetcher.head
    assert_equal Tarball.tree_sha256(Tarball.from_directory(upstream)), head.sha
    assert fetcher.head(previous_sha: head.sha).unchanged?

    File.write(File.join(upstream, "plugins", "notes", "skills", "note-taking", "SKILL.md"), "---\nname: note-taking\ndescription: Changed.\n---\n")
    moved = fetcher.head(previous_sha: head.sha)
    refute moved.unchanged?
    refute_equal head.sha, moved.sha
  end

  def test_directory_catalog_and_source_tree
    fetcher = Fetcher.for(Locator.parse(marketplace_fixture_path("basic")))
    head = fetcher.head
    files = fetcher.catalog_files(head)
    assert_equal [".claude-plugin/marketplace.json"], files.keys
    catalog = Manifest.discover(files)
    fetched = fetcher.source_tree(catalog.plugin("writing").source, head: head)
    assert_equal head.sha, fetched.sha
    assert_includes fetched.files.keys, "skills/draft/SKILL.md"
    assert_equal head.sha, fetcher.source_sha(catalog.plugin("writing").source, head: head)
  end

  def test_directory_source_tree_raises_for_a_missing_subdir
    fetcher = Fetcher.for(Locator.parse(marketplace_fixture_path("basic")))
    head = fetcher.head
    error = assert_raises(FetchError) { fetcher.source_tree(Manifest.relative("nope"), head: head) }
    assert_includes error.message, "nope has no files"
  end

  def test_directory_must_exist
    assert_raises(FetchError) { Fetcher.for(Locator.parse("./does-not-exist")).head }
  end

  # --- github ---

  def test_github_head_resolves_the_ref_and_honors_etags
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA, etag: "\"e1\"")
    fetcher = Fetcher.for(Locator.parse("acme/skills"))
    head = fetcher.head
    assert_equal SHA, head.sha
    assert_equal "\"e1\"", head.etag
    refute head.unchanged?
    assert fetcher.head(previous_sha: SHA).unchanged?

    stub_request(:get, "https://api.github.com/repos/acme/skills/commits/main").with(headers: {"If-None-Match" => "\"e1\""}).to_return(status: 304)
    cached = fetcher.head(previous_sha: SHA, previous_etag: "\"e1\"")
    assert cached.unchanged?
    assert_equal SHA, cached.sha
  end

  def test_github_uses_the_default_branch_when_no_ref_is_given
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA, ref: "trunk", default_branch: "trunk")
    assert_equal SHA, Fetcher.for(Locator.parse("acme/skills")).head.sha
    assert_requested :get, "https://api.github.com/repos/acme/skills"
  end

  def test_github_sends_the_token_to_github_hosts
    RubyLLM::Skills::Marketplace.config.github_token = "secret"
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA)
    Fetcher.for(Locator.parse("acme/skills@main")).head
    assert_requested :get, "https://api.github.com/repos/acme/skills/commits/main", headers: {"Authorization" => "Bearer secret"}
  end

  def test_github_catalog_files_skip_missing_manifests
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA)
    fetcher = Fetcher.for(Locator.parse("acme/skills"))
    files = fetcher.catalog_files(fetcher.head)
    assert_equal [".claude-plugin/marketplace.json"], files.keys
  end

  def test_github_relative_sources_share_one_tarball_download
    stub_github_marketplace("acme/skills", fixture: "basic", sha: SHA)
    fetcher = Fetcher.for(Locator.parse("acme/skills"))
    head = fetcher.head
    catalog = Manifest.discover(fetcher.catalog_files(head))
    writing = fetcher.source_tree(catalog.plugin("writing").source, head: head)
    notes = fetcher.source_tree(catalog.plugin("notes").source, head: head)
    assert_includes writing.files.keys, "skills/draft/SKILL.md"
    assert_includes notes.files.keys, "skills/note-taking/SKILL.md"
    assert_equal "https://github.com/acme/skills/tree/#{SHA}/plugins/writing", writing.upstream_url
    assert_requested :get, "https://codeload.github.com/acme/skills/tar.gz/#{SHA}", times: 1
  end

  def test_github_entries_pinned_by_sha_fetch_the_other_repository
    stub_github_marketplace("acme/remote", fixture: "codex", sha: OTHER)
    fetcher = Fetcher.for(Locator.parse("acme/skills"))
    source = Manifest.github("acme/remote", sha: OTHER, subdir: "tools")
    fetched = fetcher.source_tree(source, head: Fetcher::Head.new(sha: SHA, etag: nil, unchanged: false))
    assert_equal OTHER, fetched.sha
    assert_includes fetched.files.keys, "skills/tool-a/SKILL.md"
    assert_equal OTHER, fetcher.source_sha(source, head: nil)
    refute_requested :get, "https://api.github.com/repos/acme/remote/commits/#{OTHER}"
  end

  def test_github_entries_with_a_ref_resolve_it_once
    stub_github_marketplace("acme/remote", fixture: "codex", sha: OTHER, ref: "dev")
    fetcher = Fetcher.for(Locator.parse("acme/skills"))
    source = Manifest.github("acme/remote", ref: "dev")
    assert_equal OTHER, fetcher.source_sha(source, head: nil)
    assert_equal OTHER, fetcher.source_tree(source, head: nil).sha
    assert_requested :get, "https://api.github.com/repos/acme/remote/commits/dev", times: 1
  end

  def test_github_rate_limit_and_errors_become_fetch_errors
    stub_request(:get, "https://api.github.com/repos/acme/skills/commits/main")
      .to_return(status: 403, body: "{}", headers: {"X-RateLimit-Remaining" => "0"})
    error = assert_raises(FetchError) { Fetcher.for(Locator.parse("acme/skills@main")).head }
    assert_includes error.message, "rate limit"

    stub_request(:get, "https://api.github.com/repos/acme/skills/commits/main").to_return(status: 404, body: "{}")
    error = assert_raises(FetchError) { Fetcher.for(Locator.parse("acme/skills@main")).head }
    assert_includes error.message, "HTTP 404"
  end

  # --- gitlab ---

  def test_gitlab_head_catalog_and_tarball
    project = "group%2Fproject"
    stub_request(:get, "https://gitlab.com/api/v4/projects/#{project}").to_return(status: 200, body: JSON.generate("default_branch" => "main"))
    stub_request(:get, "https://gitlab.com/api/v4/projects/#{project}/repository/commits/main").to_return(status: 200, body: JSON.generate("id" => SHA))
    files = marketplace_fixture_files("basic")
    stub_request(:get, "https://gitlab.com/api/v4/projects/#{project}/repository/files/.claude-plugin%2Fmarketplace.json/raw?ref=#{SHA}")
      .to_return(status: 200, body: files[".claude-plugin/marketplace.json"])
    stub_request(:get, "https://gitlab.com/api/v4/projects/#{project}/repository/files/.agents%2Fplugins%2Fmarketplace.json/raw?ref=#{SHA}").to_return(status: 404)
    stub_request(:get, "https://gitlab.com/api/v4/projects/#{project}/repository/files/.cursor-plugin%2Fmarketplace.json/raw?ref=#{SHA}").to_return(status: 404)
    stub_request(:get, "https://gitlab.com/api/v4/projects/#{project}/repository/archive.tar.gz?sha=#{SHA}")
      .to_return(status: 200, body: Tarball.write(files, root: "project-#{SHA}"))

    fetcher = Fetcher.for(Locator.parse("https://gitlab.com/group/project"))
    head = fetcher.head
    assert_equal SHA, head.sha
    catalog = Manifest.discover(fetcher.catalog_files(head))
    fetched = fetcher.source_tree(catalog.plugin("notes").source, head: head)
    assert_includes fetched.files.keys, "skills/note-taking/SKILL.md"
    assert_equal "https://gitlab.com/group/project/-/tree/#{SHA}/plugins/notes", fetched.upstream_url
  end

  # --- hosted url ---

  def test_url_marketplace_head_is_the_body_hash
    body = File.read(File.join(marketplace_fixture_path("mixed"), ".claude-plugin", "marketplace.json"))
    stub_request(:get, "https://example.com/m.json").to_return(status: 200, body: body, headers: {"ETag" => "\"m1\""})
    fetcher = Fetcher.for(Locator.parse("https://example.com/m.json"))
    head = fetcher.head
    assert_equal Digest::SHA256.hexdigest(body), head.sha
    assert_equal "mixed", Manifest.discover(fetcher.catalog_files(head)).name
    error = assert_raises(FetchError) { fetcher.source_tree(Manifest.relative("./x"), head: head) }
    assert_includes error.message, "hosted marketplace.json"
  end

  def test_url_marketplace_refuses_failures
    stub_request(:get, "https://example.com/m.json").to_return(status: 500)
    assert_raises(FetchError) { Fetcher.for(Locator.parse("https://example.com/m.json")).head }
  end

  # --- archive sources ---

  def test_archive_sources_are_digest_checked_and_a_wrapping_folder_is_stripped
    files = plugin_fixture_files("basic", "plugins/notes")
    archive = Tarball.write(files, root: "notes-1.0.0")
    digest = Digest::SHA256.hexdigest(archive)
    stub_request(:get, "https://example.com/notes.tar.gz").to_return(status: 200, body: archive)
    fetcher = Fetcher.for(Locator.parse("https://example.com/m.json"))

    fetched = fetcher.source_tree(Manifest.archive("https://example.com/notes.tar.gz", sha256: digest), head: nil)
    assert_equal files, fetched.files
    assert_equal digest, fetched.sha
    assert_nil fetcher.source_sha(Manifest.archive("https://example.com/notes.tar.gz"), head: nil)

    error = assert_raises(FetchError) { fetcher.source_tree(Manifest.archive("https://example.com/notes.tar.gz", sha256: "0" * 64), head: nil) }
    assert_includes error.message, "sha256 mismatch"
  end

  def test_unsupported_sources_cannot_be_fetched
    fetcher = Fetcher.for(Locator.parse(marketplace_fixture_path("mixed")))
    catalog = Manifest.discover(fetcher.catalog_files(fetcher.head))
    error = assert_raises(FetchError) { fetcher.source_tree(catalog.plugin("npm-thing").source, head: fetcher.head) }
    assert_includes error.message, "npm_source"
  end
end
