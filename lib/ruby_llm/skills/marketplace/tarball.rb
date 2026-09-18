# frozen_string_literal: true

require "rubygems/package"
require "zlib"
require "stringio"
require "digest"
require "fileutils"
require "pathname"

module RubyLLM
  module Skills
    module Marketplace
      # The one tar.gz reader for upstream content: every entry path is
      # cleaned and refused when it escapes (`..`, absolute); anything but a
      # regular file or directory (symlinks, hardlinks, devices, FIFOs) is
      # dropped, never followed or written; the archive, each file and the
      # file count are capped. GitHub and GitLab archives wrap the repository
      # in one root directory, which +strip_root+ removes.
      #
      # Trees are plain hashes of `"relative/path" => bytes`.
      #
      module Tarball
        REGULAR = ["0", "\0"].freeze
        DIRECTORY = "5"
        EXTENDED_HEADERS = %w[g x].freeze

        class << self
          # @param archive [String] tar.gz bytes
          # @param strip_root [Boolean] drop the single wrapping directory
          # @param subdir [String, nil] keep only this directory, re-rooted
          # @return [Hash{String => String}] the files
          # @raise [InvalidPluginError]
          def read(archive, strip_root: true, subdir: nil, max_bytes: config.max_archive_bytes,
            max_file_bytes: config.max_file_bytes, max_files: config.max_files)
            raise InvalidPluginError, "archive is empty" if archive.to_s.empty?
            raise InvalidPluginError, "archive exceeds #{max_bytes} bytes" if archive.bytesize > max_bytes

            files = {}
            total = 0
            root = nil
            prefix = clean_prefix(subdir)
            Zlib::GzipReader.wrap(StringIO.new(archive)) do |gz|
              Gem::Package::TarReader.new(gz) do |tar|
                tar.each do |entry|
                  typeflag = entry.header.typeflag
                  next if EXTENDED_HEADERS.include?(typeflag)

                  parts = clean_path(entry.full_name).split("/")
                  if strip_root
                    root ||= parts.first
                    raise InvalidPluginError, "archive has more than one root (#{root.inspect}, #{parts.first.inspect})" unless parts.first == root

                    parts = parts.drop(1)
                  end
                  next if typeflag == DIRECTORY || entry.directory?
                  next unless REGULAR.include?(typeflag) || entry.file?
                  next if parts.empty?

                  rel = parts.join("/")
                  unless prefix.empty?
                    next unless rel.start_with?("#{prefix}/")

                    rel = rel.delete_prefix("#{prefix}/")
                  end
                  raise InvalidPluginError, "archive file #{entry.full_name.inspect} exceeds #{max_file_bytes} bytes" if entry.size > max_file_bytes
                  raise InvalidPluginError, "archive has more than #{max_files} files" if files.size >= max_files
                  raise InvalidPluginError, "archive expands past #{max_bytes} bytes" if (total += entry.size) > max_bytes

                  files[rel] = entry.read.to_s.b
                end
              end
            end
            raise InvalidPluginError, "archive has no files#{" under #{prefix}" unless prefix.empty?}" if files.empty?

            files
          rescue Zlib::Error, Gem::Package::TarInvalidError => e
            raise InvalidPluginError, "archive is not a valid tar.gz (#{e.class.name.split("::").last})"
          end

          # `..`, absolute paths, empty names and NUL bytes are refused before
          # any path is joined to a directory.
          def clean_path(name)
            raw = name.to_s.strip
            raise InvalidPluginError, "unsafe archive path #{name.inspect}" if raw.empty? || raw.include?("\0") || raw.start_with?("/") || raw.include?("\\")

            cleaned = Pathname.new(raw).cleanpath.to_s
            raise InvalidPluginError, "unsafe archive path #{name.inspect}" if cleaned.empty? || cleaned == "." || cleaned == ".." || cleaned.start_with?("../", "/")

            cleaned
          end

          # `{ "path" => bytes }` to tar.gz bytes, entries sorted and the
          # mtime zeroed so the same tree always yields the same archive.
          def write(files, root: nil)
            io = StringIO.new
            Zlib::GzipWriter.wrap(io) do |gz|
              gz.mtime = 0
              Gem::Package::TarWriter.new(gz) do |tar|
                files.sort.each do |path, data|
                  full = root ? "#{root}/#{path}" : path
                  bytes = data.to_s.b
                  tar.add_file_simple(full, 0o644, bytes.bytesize) { |f| f.write(bytes) }
                end
              end
            end
            io.string
          end

          # The directory as `{ "path" => bytes }` (regular files only).
          def from_directory(dir, max_bytes: config.max_archive_bytes, max_file_bytes: config.max_file_bytes, max_files: config.max_files)
            base = Pathname.new(dir)
            files = {}
            total = 0
            Dir.glob("**/*", File::FNM_DOTMATCH, base: base.to_s).sort.each do |rel|
              next if rel == "." || rel.end_with?("/.") || rel.split("/").include?("..")

              full = base.join(rel)
              next if full.symlink? || !full.file?
              raise InvalidPluginError, "#{rel} exceeds #{max_file_bytes} bytes" if full.size > max_file_bytes
              raise InvalidPluginError, "#{dir} has more than #{max_files} files" if files.size >= max_files
              raise InvalidPluginError, "#{dir} holds more than #{max_bytes} bytes" if (total += full.size) > max_bytes

              files[rel] = full.binread
            end
            files
          end

          # Writes the tree under +dir+, creating parents; replaces nothing else.
          def write_directory(files, dir)
            files.each do |path, data|
              target = File.join(dir, path)
              FileUtils.mkdir_p(File.dirname(target))
              File.binwrite(target, data)
            end
            dir
          end

          # sha256 over the sorted paths and content hashes: the tree's identity.
          def tree_sha256(files)
            digest = Digest::SHA256.new
            files.sort.each do |path, data|
              digest << path << "\0" << Digest::SHA256.hexdigest(data.to_s) << "\n"
            end
            digest.hexdigest
          end

          private

          def config
            Marketplace.config
          end

          def clean_prefix(subdir)
            subdir.to_s.delete_prefix("./").delete_suffix("/")
          end
        end
      end
    end
  end
end
