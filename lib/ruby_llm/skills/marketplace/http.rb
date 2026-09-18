# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "json"

module RubyLLM
  module Skills
    module Marketplace
      # The one HTTP door for marketplace fetches: HTTPS only, a body cap,
      # redirects followed by hand, conditional requests through ETags.
      #
      # Two admission modes: +hosts:+ for the adapters' own well-known hosts,
      # +public: true+ for a URL a marketplace author supplied, where every
      # hop must pass +Config#url_guard+ when one is configured.
      #
      module Http
        OPEN_TIMEOUT = 10
        READ_TIMEOUT = 120
        MAX_REDIRECTS = 3

        Response = Data.define(:status, :body, :headers) do
          def success? = status.between?(200, 299)

          def not_modified? = status == 304

          def not_found? = status == 404

          def etag
            value = headers["etag"].to_s
            value.empty? ? nil : value
          end
        end

        class << self
          # @param url [String] an https URL
          # @param hosts [Array<String>] hosts admitted by name
          # @param public [Boolean] admit any https host that passes the url_guard
          # @param headers [Hash] extra request headers
          # @param max_bytes [Integer] abandon the body past this many bytes
          # @param etag [String, nil] sent as If-None-Match
          # @return [Response]
          # @raise [FetchError]
          def get(url, hosts: [], public: false, headers: {}, max_bytes: Marketplace.config.max_archive_bytes, etag: nil)
            uri = parse(url)
            request_headers = {"User-Agent" => Marketplace.config.user_agent}.merge(headers)
            request_headers["If-None-Match"] = etag if etag

            (MAX_REDIRECTS + 1).times do
              address = admit!(uri, hosts: hosts, public: public)
              response = perform(uri, request_headers, max_bytes, address: address)
              location = response.headers["location"]
              return response unless response.status.between?(300, 399) && location

              uri = parse(URI.join(uri.to_s, location).to_s)
            end

            raise FetchError, "#{uri.host}: too many redirects"
          rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
            raise FetchError, "#{uri&.host}: #{e.class.name}"
          end

          def json(response)
            parsed = JSON.parse(response.body.to_s)
            parsed.is_a?(Hash) ? parsed : {}
          rescue JSON::ParserError
            raise FetchError, "malformed JSON response"
          end

          private

          def parse(url)
            URI.parse(url.to_s)
          rescue URI::InvalidURIError
            raise FetchError, "invalid URL #{url.to_s.inspect}"
          end

          # The address to connect to (nil: by name) once the hop is admitted.
          def admit!(uri, hosts:, public:)
            host = uri.host.to_s.downcase
            raise FetchError, "refusing #{uri}: not an https URL" unless uri.is_a?(URI::HTTPS) && !host.empty?
            raise FetchError, "refusing #{uri}: URLs with credentials are not allowed" if uri.userinfo
            return nil if hosts.map(&:downcase).include?(host)
            raise FetchError, "refusing #{host.inspect}: not an allowlisted https host" unless public

            address = Marketplace.config.url_guard&.call(uri)
            address.is_a?(String) ? address : nil
          end

          # Streams the body and stops reading the moment it passes the cap,
          # so an upstream that answers with gigabytes never occupies more
          # than the cap in memory. Pinned to +address+ when given, Net::HTTP
          # still names the host for SNI and the certificate check.
          def perform(uri, headers, max_bytes, address: nil)
            body = String.new(encoding: Encoding::BINARY)
            http = Net::HTTP.new(uri.host, uri.port)
            http.ipaddr = address if address
            http.use_ssl = true
            http.open_timeout = OPEN_TIMEOUT
            http.read_timeout = READ_TIMEOUT
            http.start do
              request = Net::HTTP::Get.new(uri.request_uri, headers)
              http.request(request) do |response|
                response.read_body do |chunk|
                  raise FetchError, "#{uri.host}: response exceeds #{max_bytes} bytes" if body.bytesize + chunk.bytesize > max_bytes

                  body << chunk.b
                end
                return Response.new(status: response.code.to_i, body: body, headers: response_headers(response))
              end
            end
          end

          def response_headers(response)
            response.each_header.to_h { |key, value| [key.downcase, value] }
          end
        end
      end
    end
  end
end
