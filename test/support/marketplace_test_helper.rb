# frozen_string_literal: true

require "tmpdir"
require "webmock/minitest"

# Shared setup for the marketplace tests: a fresh configuration, a scratch
# root and lockfile, fixture marketplaces on disk, and WebMock stubs for a
# GitHub repository built from a fixture directory. Real HTTP never happens.
module MarketplaceTestHelper
  Marketplace = RubyLLM::Skills::Marketplace

  def setup
    super
    Marketplace.reset_config!
    Marketplace.config.github_token = nil
    @tmpdir = Dir.mktmpdir("ruby_llm_skills_marketplace")
    VCR.turn_off!(ignore_cassettes: true) if defined?(VCR)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    Marketplace.reset_config!
    VCR.turn_on! if defined?(VCR)
    super
  end

  def marketplace_fixture_path(name)
    File.join(fixtures_path, "marketplaces", name)
  end

  def marketplace_fixture_files(name)
    Marketplace::Tarball.from_directory(marketplace_fixture_path(name))
  end

  def plugin_fixture_files(marketplace, plugin_path)
    marketplace_fixture_files(marketplace)
      .select { |path, _| path.start_with?("#{plugin_path}/") }
      .transform_keys { |path| path.delete_prefix("#{plugin_path}/") }
  end

  def scratch_root
    File.join(@tmpdir, "vendor", "skills")
  end

  def scratch_lockfile
    File.join(@tmpdir, "skills.lock.json")
  end

  def registry
    @registry ||= Marketplace::Registry.new(root: scratch_root, lockfile: scratch_lockfile)
  end

  # A copy of a fixture marketplace the test may change.
  def copy_marketplace_fixture(name)
    target = File.join(@tmpdir, "upstream", name)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp_r(marketplace_fixture_path(name), target)
    target
  end

  def lockfile_json
    JSON.parse(File.read(scratch_lockfile))
  end

  def installed_files(marketplace, plugin)
    dir = File.join(scratch_root, marketplace, plugin)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).select { |rel| File.file?(File.join(dir, rel)) }.sort
  end

  # Stubs api.github.com, raw.githubusercontent.com and codeload.github.com
  # for +repo+ serving the fixture marketplace +fixture+ at +sha+.
  def stub_github_marketplace(repo, fixture:, sha:, ref: "main", default_branch: "main", etag: nil)
    files = marketplace_fixture_files(fixture)
    stub_request(:get, "https://api.github.com/repos/#{repo}")
      .to_return(status: 200, body: JSON.generate("default_branch" => default_branch), headers: {"Content-Type" => "application/json"})
    stub_request(:get, "https://api.github.com/repos/#{repo}/commits/#{ref}")
      .to_return(status: 200, body: JSON.generate("sha" => sha), headers: {"Content-Type" => "application/json", "ETag" => etag}.compact)
    stub_request(:get, "https://api.github.com/repos/#{repo}/commits/#{sha}")
      .to_return(status: 200, body: JSON.generate("sha" => sha), headers: {"Content-Type" => "application/json"})
    Marketplace::Manifest::PATHS.each do |path|
      stub = stub_request(:get, "https://raw.githubusercontent.com/#{repo}/#{sha}/#{path}")
      if files.key?(path)
        stub.to_return(status: 200, body: files[path])
      else
        stub.to_return(status: 404, body: "Not Found")
      end
    end
    stub_request(:get, "https://codeload.github.com/#{repo}/tar.gz/#{sha}")
      .to_return(status: 200, body: Marketplace::Tarball.write(files, root: "#{repo.split("/").last}-#{sha}"))
  end
end
