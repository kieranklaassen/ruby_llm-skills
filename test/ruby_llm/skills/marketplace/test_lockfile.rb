# frozen_string_literal: true

require "test_helper"
require "support/marketplace_test_helper"

class RubyLLM::Skills::Marketplace::TestLockfile < Minitest::Test
  include MarketplaceTestHelper

  Lockfile = RubyLLM::Skills::Marketplace::Lockfile
  LockfileError = RubyLLM::Skills::Marketplace::LockfileError

  def test_a_missing_file_is_an_empty_lockfile
    lockfile = Lockfile.load(scratch_lockfile)
    assert_equal [], lockfile.names
    assert_nil lockfile.marketplace("x")
    assert_equal({}, lockfile.plugins("x"))
  end

  def test_save_writes_sorted_pretty_json_with_a_trailing_newline
    lockfile = Lockfile.load(scratch_lockfile)
    lockfile.set_marketplace("zeta", "kind" => "github", "locator" => "z/z", "commit" => "c")
    lockfile.set_plugin("zeta", "b", "version" => "1")
    lockfile.set_plugin("zeta", "a", "version" => "2")
    lockfile.set_marketplace("alpha", "kind" => "directory", "locator" => "./a", "commit" => "d")
    lockfile.save

    text = File.read(scratch_lockfile)
    assert text.end_with?("}\n")
    data = JSON.parse(text)
    assert_equal 1, data["version"]
    assert_equal %w[alpha zeta], data["marketplaces"].keys
    assert_equal %w[a b], data["marketplaces"]["zeta"]["plugins"].keys
    assert_equal %w[kind locator commit plugins], data["marketplaces"]["zeta"].keys
  end

  def test_set_marketplace_keeps_plugins_and_replaces_fields
    lockfile = Lockfile.load(scratch_lockfile)
    lockfile.set_marketplace("m", "kind" => "github", "locator" => "a/b", "ref" => "v1", "commit" => "c1")
    lockfile.set_plugin("m", "p", "version" => "1")
    lockfile.set_marketplace("m", "kind" => "github", "locator" => "a/b", "commit" => "c2")
    entry = lockfile.marketplace("m")
    assert_equal "c2", entry["commit"]
    refute entry.key?("ref")
    assert_equal({"version" => "1"}, lockfile.plugin("m", "p"))
  end

  def test_delete_marketplace_and_plugin
    lockfile = Lockfile.load(scratch_lockfile)
    lockfile.set_plugin("m", "p", "version" => "1")
    lockfile.set_plugin("m", "q", "version" => "1")
    lockfile.delete_plugin("m", "p")
    assert_equal ["q"], lockfile.plugins("m").keys
    lockfile.delete_marketplace("m")
    assert_equal [], lockfile.names
  end

  def test_load_round_trips
    lockfile = Lockfile.load(scratch_lockfile)
    lockfile.set_marketplace("m", "kind" => "github", "locator" => "a/b", "commit" => "c")
    lockfile.set_plugin("m", "p", "version" => "1", "skills" => %w[x y])
    lockfile.save
    assert_equal lockfile.to_h, Lockfile.load(scratch_lockfile).to_h
  end

  def test_load_rejects_malformed_files
    File.write(scratch_lockfile, "nope")
    assert_raises(LockfileError) { Lockfile.load(scratch_lockfile) }

    File.write(scratch_lockfile, "[]")
    assert_raises(LockfileError) { Lockfile.load(scratch_lockfile) }

    File.write(scratch_lockfile, JSON.generate("version" => 99, "marketplaces" => {}))
    error = assert_raises(LockfileError) { Lockfile.load(scratch_lockfile) }
    assert_includes error.message, "version 99"

    File.write(scratch_lockfile, JSON.generate("version" => 1))
    assert_raises(LockfileError) { Lockfile.load(scratch_lockfile) }
  end
end
