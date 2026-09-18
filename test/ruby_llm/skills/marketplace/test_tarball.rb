# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestTarball < Minitest::Test
  include MarketplaceTestHelper

  Tarball = RubyLLM::Skills::Marketplace::Tarball
  InvalidPluginError = RubyLLM::Skills::Marketplace::InvalidPluginError

  def files
    {"skills/a/SKILL.md" => "---\nname: a\ndescription: A\n---\n", "README.md" => "hi", "docs/deep/x.txt" => "x"}
  end

  def test_write_then_read_round_trips_without_root
    archive = Tarball.write(files)
    assert_equal files, Tarball.read(archive, strip_root: false)
  end

  def test_read_strips_a_single_root_directory
    archive = Tarball.write(files, root: "repo-abc123")
    assert_equal files, Tarball.read(archive)
  end

  def test_read_refuses_two_roots_when_stripping
    archive = Tarball.write({"one/a.txt" => "a", "two/b.txt" => "b"})
    error = assert_raises(InvalidPluginError) { Tarball.read(archive) }
    assert_includes error.message, "more than one root"
  end

  def test_read_keeps_only_the_subdir_re_rooted
    archive = Tarball.write(files, root: "repo")
    assert_equal({"deep/x.txt" => "x"}, Tarball.read(archive, subdir: "./docs/"))
  end

  def test_read_raises_when_the_subdir_has_no_files
    archive = Tarball.write(files, root: "repo")
    error = assert_raises(InvalidPluginError) { Tarball.read(archive, subdir: "nope") }
    assert_includes error.message, "under nope"
  end

  def test_write_is_deterministic
    assert_equal Tarball.write(files), Tarball.write(files.to_a.reverse.to_h)
  end

  def test_read_refuses_escaping_paths
    archive = tar_with_entries([["../evil.txt", "x"]])
    assert_raises(InvalidPluginError) { Tarball.read(archive, strip_root: false) }
  end

  def test_read_refuses_absolute_paths
    archive = tar_with_entries([["/etc/passwd", "x"]])
    assert_raises(InvalidPluginError) { Tarball.read(archive, strip_root: false) }
  end

  def test_read_drops_symlinks
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        tar.add_file_simple("a.txt", 0o644, 1) { |f| f.write("a") }
        tar.add_symlink("link", "a.txt", 0o644)
      end
    end
    assert_equal({"a.txt" => "a"}, Tarball.read(io.string, strip_root: false))
  end

  def test_read_enforces_the_file_count_cap
    archive = Tarball.write({"a" => "1", "b" => "2", "c" => "3"})
    error = assert_raises(InvalidPluginError) { Tarball.read(archive, strip_root: false, max_files: 2) }
    assert_includes error.message, "more than 2 files"
  end

  def test_read_enforces_the_file_size_cap
    archive = Tarball.write({"big" => "x" * 100})
    assert_raises(InvalidPluginError) { Tarball.read(archive, strip_root: false, max_file_bytes: 10) }
  end

  def test_read_enforces_the_expanded_size_cap
    archive = Tarball.write({"a" => "x" * 5000, "b" => "y" * 5000})
    assert_operator archive.bytesize, :<, 5000
    error = assert_raises(InvalidPluginError) { Tarball.read(archive, strip_root: false, max_bytes: 5000) }
    assert_includes error.message, "expands past 5000 bytes"
  end

  def test_read_rejects_garbage
    assert_raises(InvalidPluginError) { Tarball.read("not a tarball", strip_root: false) }
    assert_raises(InvalidPluginError) { Tarball.read("", strip_root: false) }
  end

  def test_from_directory_reads_regular_files_only
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "skills", "a"))
      File.write(File.join(dir, "skills", "a", "SKILL.md"), "x")
      File.write(File.join(dir, ".hidden"), "h")
      File.symlink(File.join(dir, ".hidden"), File.join(dir, "link"))
      assert_equal({".hidden" => "h", "skills/a/SKILL.md" => "x"}, Tarball.from_directory(dir))
    end
  end

  def test_tree_sha256_is_order_independent_and_content_sensitive
    a = Tarball.tree_sha256(files)
    assert_equal a, Tarball.tree_sha256(files.to_a.reverse.to_h)
    refute_equal a, Tarball.tree_sha256(files.merge("README.md" => "changed"))
    refute_equal a, Tarball.tree_sha256(files.merge("extra" => ""))
  end

  def test_write_directory_writes_every_file
    Dir.mktmpdir do |dir|
      Tarball.write_directory(files, dir)
      assert_equal "x", File.read(File.join(dir, "docs", "deep", "x.txt"))
      assert_equal files, Tarball.from_directory(dir)
    end
  end

  private

  def tar_with_entries(entries)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        entries.each { |name, data| tar.add_file_simple(name, 0o644, data.bytesize) { |f| f.write(data) } }
      end
    end
    io.string
  end
end
