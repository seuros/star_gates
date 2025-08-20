# frozen_string_literal: true

require_relative 'base_adapter'

module StarGates
  module Adapters
    class RedisAdapter < BaseAdapter
      def initialize(config = {})
        super
        @redis = config[:redis] || redis_from_config
        @key_prefix = config[:key_prefix] || 'star_gates'
        @default_ttl = config[:default_ttl] || 3600 # 1 hour
      end

      def store(key, value)
        serialized = serialize(value)
        @redis.set(prefixed_key(key), serialized)
      end

      def fetch(key)
        value = @redis.get(prefixed_key(key))
        value ? deserialize(value) : nil
      end

      def delete(key)
        @redis.del(prefixed_key(key))
      end

      def exists?(key)
        @redis.exists?(prefixed_key(key)).positive?
      end

      def cache_fetch(key, expires_in: nil, &block)
        prefixed = prefixed_key(key)
        cached = @redis.get(prefixed)

        if cached
          deserialize(cached)
        elsif block_given?
          value = block.call
          if value
            serialized = serialize(value)
            ttl = expires_in || @default_ttl
            @redis.setex(prefixed, ttl, serialized)
          end
          value
        end
      end

      def cache_write(key, value, expires_in: nil)
        serialized = serialize(value)
        ttl = expires_in || @default_ttl
        @redis.setex(prefixed_key(key), ttl, serialized)
      end

      def cache_delete(key)
        @redis.del(prefixed_key(key))
      end

      def publish(topic, message)
        @redis.publish(topic_key(topic), serialize(message))
      end

      def subscribe(topic, &block)
        # Redis pub/sub requires a dedicated connection
        # This is a simplified version - in production, use a separate subscriber thread
        @redis.subscribe(topic_key(topic)) do |on|
          on.message do |_channel, message|
            block.call(deserialize(message))
          end
        end
      end

      def healthy?
        @redis.ping == 'PONG'
      rescue StandardError
        false
      end

      private

      def prefixed_key(key)
        "#{@key_prefix}:#{key}"
      end

      def topic_key(topic)
        "#{@key_prefix}:topics:#{topic}"
      end

      def serialize(value)
        case value
        when String
          value
        when Symbol
          value.to_s
        else
          JSON.generate(value)
        end
      end

      def deserialize(value)
        JSON.parse(value)
      rescue JSON::ParserError
        value
      end

      def redis_from_config
        raise ArgumentError, "Redis gem not available. Install with: gem 'redis'" unless defined?(Redis)

        # Try to use existing Redis configuration
        if defined?(Rails) && Rails.application.config.respond_to?(:redis)
          Redis.new(Rails.application.config.redis)
        else
          Redis.new
        end
      end
    end
  end
end
