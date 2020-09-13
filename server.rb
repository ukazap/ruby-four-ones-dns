#!/usr/bin/env ruby
require 'async/dns'
require 'async/http'
require 'trenni/uri'

PORT = ENV.fetch('ONE_ONE_ONE_ONE_PORT') { 5300 }
BINDING = ENV.fetch('ONE_ONE_ONE_ONE_PORT') { '0.0.0.0' }

module OneOneOneOne
  class Server < Async::DNS::Server
    def process(_name, _resource_class, transaction)
      @resolver ||= Resolver.new
      transaction.passthrough!(@resolver)
    end
  end

  class Resolver < Async::DNS::Resolver
    def initialize(origin: nil, logger: Async.logger, timeout: DEFAULT_TIMEOUT)
      super([], origin: nil, logger: Async.logger, timeout: DEFAULT_TIMEOUT)

      @http_endpoint = Async::HTTP::Endpoint.parse("https://cloudflare-dns.com/dns-query")
      @http_client = Async::HTTP::Client.new(@http_endpoint)
    end

    def dispatch_request(message, task: Async::Task.current)
      q_name, q_type = message.question.first

      name = q_name.to_s
      type = q_type.name.split("::".freeze).last

      request_uri = Trenni::URI(@http_endpoint.url.request_uri, dns: Base64.encode64(message.encode))
      
      begin
        response = nil

        task.with_timeout(@timeout) do
          @logger.debug "[#{message.id}] -> requesting #{name} (#{type})" if @logger
          
          http_response = @http_client.get(request_uri.to_s, {})
          response = Resolv::DNS::Message.decode(http_response.read)
          
          @logger.debug "[#{message.id}] <- got #{name} (#{type})" if @logger
        end

        return response if valid_response(message, response)
      rescue Async::TimeoutError
        @logger.debug "[#{message.id}] Request timed out!" if @logger
      rescue Resolv::DNS::DecodeError
        @logger.warn "[#{message.id}] Error while decoding data from network: #{$!}!" if @logger
      end
      
      return nil
    end
  end
end

server = OneOneOneOne::Server.new([
  [:udp, BINDING, PORT],
  [:tcp, BINDING, PORT]
])

server.run