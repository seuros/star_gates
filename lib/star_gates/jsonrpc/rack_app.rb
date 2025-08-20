# frozen_string_literal: true

require_relative 'base_handler'

module StarGates
  module JsonRpc
    class RackApp
      def initialize(feature_service)
        @handler = BaseHandler.new(feature_service)
      end

      def call(env)
        request = Rack::Request.new(env)

        # Only handle POST requests
        return method_not_allowed_response unless request.post?

        # Check content type
        content_type = request.content_type
        return unsupported_media_type_response unless content_type&.include?('application/json')

        # Read request body
        body = request.body.read
        request.body.rewind

        # Handle the JSON-RPC request
        response_body = @handler.handle_request(body)

        # Return successful response
        [
          200,
          {
            'Content-Type' => 'application/json',
            'Content-Length' => response_body.bytesize.to_s,
            'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => 'POST, OPTIONS',
            'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
          },
          [response_body]
        ]
      rescue StandardError => e
        error_response = {
          jsonrpc: '2.0',
          error: {
            code: -32_603,
            message: "Internal error: #{e.message}"
          },
          id: nil
        }.to_json

        [
          500,
          {
            'Content-Type' => 'application/json',
            'Content-Length' => error_response.bytesize.to_s
          },
          [error_response]
        ]
      end

      private

      def method_not_allowed_response
        [
          405,
          {
            'Content-Type' => 'application/json',
            'Allow' => 'POST'
          },
          [method_not_allowed_body]
        ]
      end

      def method_not_allowed_body
        {
          jsonrpc: '2.0',
          error: {
            code: -32_601,
            message: 'Method not allowed. Use POST.'
          },
          id: nil
        }.to_json
      end

      def unsupported_media_type_response
        [
          415,
          {
            'Content-Type' => 'application/json'
          },
          [unsupported_media_type_body]
        ]
      end

      def unsupported_media_type_body
        {
          jsonrpc: '2.0',
          error: {
            code: -32_700,
            message: 'Unsupported media type. Use application/json.'
          },
          id: nil
        }.to_json
      end
    end
  end
end
