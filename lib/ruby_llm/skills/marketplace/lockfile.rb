# frozen_string_literal: true

require "json"
require "fileutils"

module RubyLLM
  module Skills
    module Marketplace
      # The record of every added marketplace and installed plugin, with the
      # commit and tree each resolved to, so `install` reproduces the same
      # trees on another machine. JSON, keys sorted, one trailing newline.
      #
      #   {
      #     "version": 1,
      #     "marketplaces": {
      #       "compound-writing": {
      #         "kind": "github", "locator": "EveryInc/compound-writing", "ref": "main",
      #         "commit": "…",
      #         "plugins": {
      #           "compound-writing": {
      #             "version": "2.4.1", "version_kind": "manifest", "commit": "…",
      #             "tree_sha256": "…", "source": { "kind": "relative", "path": "" },
      #             "skills": ["cw-draft", "…"]
      #           }
      #         }
      #       }
      #     }
      #   }
      #
      class Lockfile
        VERSION = 1

        attr_reader :path, :marketplaces

        # @param path [String] the lockfile; a missing file is an empty lockfile
        # @raise [LockfileError]
        def self.load(path)
          return new(path) unless File.exist?(path)

          data = JSON.parse(File.read(path))
          raise LockfileError, "#{path} is not a JSON object" unless data.is_a?(Hash)
          raise LockfileError, "#{path} has lockfile version #{data["version"].inspect}; this gem reads version #{VERSION}" unless data["version"] == VERSION

          marketplaces = data["marketplaces"]
          raise LockfileError, "#{path} has no marketplaces object" unless marketplaces.is_a?(Hash)

          marketplaces.each do |name, entry|
            raise LockfileError, "#{path}: marketplace #{name.inspect} is not an object" unless entry.is_a?(Hash)
            raise LockfileError, "#{path}: marketplace #{name.inspect} has no plugins object" unless entry.fetch("plugins", {}).is_a?(Hash)
          end
          new(path, marketplaces)
        rescue JSON::ParserError => e
          raise LockfileError, "#{path} is not valid JSON (#{e.message[0, 80]})"
        end

        def initialize(path, marketplaces = {})
          @path = path.to_s
          @marketplaces = marketplaces
        end

        def marketplace(name)
          @marketplaces[name.to_s]
        end

        def names
          @marketplaces.keys.sort
        end

        def plugins(name)
          marketplace(name)&.fetch("plugins", nil) || {}
        end

        def plugin(name, plugin)
          plugins(name)[plugin.to_s]
        end

        # Records a marketplace, keeping its plugins unless +data+ carries some.
        def set_marketplace(name, data)
          existing = marketplace(name) || {}
          plugins = data.fetch("plugins", existing.fetch("plugins", {}))
          @marketplaces[name.to_s] = data.except("plugins").merge("plugins" => plugins)
        end

        def delete_marketplace(name)
          @marketplaces.delete(name.to_s)
        end

        def set_plugin(name, plugin, data)
          set_marketplace(name, {}) unless marketplace(name)
          @marketplaces[name.to_s]["plugins"][plugin.to_s] = data
        end

        def delete_plugin(name, plugin)
          plugins(name).delete(plugin.to_s)
        end

        # Marketplaces and plugins sorted by name; each entry keeps its field order.
        def to_h
          marketplaces = @marketplaces.sort.to_h do |name, data|
            [name, data.merge("plugins" => data.fetch("plugins", {}).sort.to_h)]
          end
          {"version" => VERSION, "marketplaces" => marketplaces}
        end

        def save
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, "#{JSON.pretty_generate(to_h)}\n")
          self
        end
      end
    end
  end
end
