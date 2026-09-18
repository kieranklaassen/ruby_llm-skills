# frozen_string_literal: true

require "uri"

module RubyLLM
  module Skills
    module Marketplace
      # What a person types to name a marketplace: `owner/repo`, `owner/repo@ref`,
      # a github.com or gitlab.com repository URL (with an optional `/tree/<ref>`),
      # an https:// URL ending in `.json` (a hosted marketplace file), or a
      # local directory.
      #
      module Locator
        # A marketplace upstream: +kind+ is "github", "gitlab", "url" or "directory".
        Source = Data.define(:kind, :locator, :ref) do
          def to_h
            {"kind" => kind, "locator" => locator, "ref" => ref}.compact
          end

          def self.from_h(hash)
            hash = hash.to_h.transform_keys(&:to_s)
            new(kind: hash["kind"], locator: hash["locator"], ref: hash["ref"])
          end

          # Pinned when the ref is a full commit sha.
          def pinned? = ref.to_s.match?(Manifest::SHA_PATTERN)

          def to_s
            ref ? "#{locator}@#{ref}" : locator
          end
        end

        HOSTS = {"github.com" => "github", "gitlab.com" => "gitlab"}.freeze
        MAX_LENGTH = 500
        REF_PATTERN = %r{\A\w[\w./-]{0,199}\z}

        class << self
          # @param text [String]
          # @param ref [String, nil] a branch, tag or sha; overrides an `@ref` suffix
          # @return [Source]
          # @raise [ArgumentError]
          def parse(text, ref: nil)
            text = text.to_s.strip
            raise ArgumentError, "marketplace locator is empty" if text.empty?
            raise ArgumentError, "marketplace locator is too long" if text.length > MAX_LENGTH

            source = if text.match?(%r{\Ahttps?://}i)
              from_url(text)
            elsif text.start_with?("./", "../", "/") || File.directory?(text)
              Source.new(kind: "directory", locator: text, ref: nil)
            else
              from_shorthand(text)
            end
            ref = Manifest.presence(ref)
            return source unless ref
            raise ArgumentError, "a #{source.kind} marketplace has no ref" unless %w[github gitlab].include?(source.kind)
            raise ArgumentError, "invalid ref #{ref.inspect}" unless ref.match?(REF_PATTERN)

            Source.new(kind: source.kind, locator: source.locator, ref: ref)
          end

          private

          def from_shorthand(text)
            repo, ref = text.split("@", 2)
            valid_ref = ref.nil? || ref.match?(REF_PATTERN)
            raise ArgumentError, "invalid marketplace locator #{text.inspect}" unless repo.match?(Manifest::REPO_PATTERN) && valid_ref

            Source.new(kind: "github", locator: repo, ref: ref)
          end

          def from_url(text)
            uri = URI.parse(text)
            raise ArgumentError, "marketplace URLs must be https" unless uri.scheme&.downcase == "https" && Manifest.presence(uri.host)
            raise ArgumentError, "marketplace URLs must not carry credentials" if uri.userinfo

            kind = HOSTS[uri.host.downcase]
            return Source.new(kind: "url", locator: text, ref: nil) if kind.nil? && uri.path.end_with?(".json")
            raise ArgumentError, "unsupported marketplace host #{uri.host.inspect}" if kind.nil?

            segments = uri.path.split("/").reject(&:empty?)
            depth = repo_depth(kind, segments)
            raise ArgumentError, "invalid repository URL #{text.inspect}" if depth < 2 || segments.size < depth

            repo = segments.first(depth).join("/").delete_suffix(".git")
            pattern = (kind == "gitlab") ? Manifest::PROJECT_PATTERN : Manifest::REPO_PATTERN
            raise ArgumentError, "invalid repository URL #{text.inspect}" unless repo.match?(pattern)

            ref = ref_from_segments(segments, depth)
            Source.new(kind: kind, locator: repo, ref: Manifest.presence(ref))
          rescue URI::InvalidURIError
            raise ArgumentError, "invalid marketplace URL #{text.inspect}"
          end

          # `/tree/<ref>` on GitHub, `/-/tree/<ref>` on GitLab.
          def ref_from_segments(segments, depth)
            marker = segments[depth]
            return nil unless %w[tree -].include?(marker)

            segments.drop((marker == "-") ? depth + 2 : depth + 1).join("/")
          end

          # Two segments name a GitHub repository; on GitLab everything before
          # the `/-/` (or a legacy `/tree/`) separator, because a project there
          # lives under nested groups.
          def repo_depth(kind, segments)
            return 2 unless kind == "gitlab"

            segments.index { |segment| %w[- tree].include?(segment) } || segments.size
          end
        end
      end
    end
  end
end
