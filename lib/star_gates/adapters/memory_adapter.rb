# frozen_string_literal: true

require_relative 'base_adapter'
require 'concurrent'

module StarGates
  module Adapters
    class MemoryAdapter < BaseAdapter
      def initialize(config = {})
        super
        @storage = Concurrent::Hash.new
        @subscribers = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Array.new }
        @mutex = Mutex.new
      end

      def store(key, value)
        @storage[key] = value
      end

      def fetch(key)
        @storage[key]
      end

      def delete(key)
        @storage.delete(key)
      end

      def exists?(key)
        @storage.key?(key)
      end

      def cache_fetch(key, expires_in: nil, &block)
        # Memory adapter doesn't support expiration, but we can implement basic caching
        if @storage.key?(key)
          @storage[key]
        elsif block_given?
          value = block.call
          @storage[key] = value if value
          value
        end
      end

      def cache_write(key, value, expires_in: nil)
        @storage[key] = value
      end

      def cache_delete(key)
        @storage.delete(key)
      end

      def publish(topic, message)
        subscribers = @subscribers[topic].to_a
        return if subscribers.empty?

        # Publish to subscribers in background fibers if available
        if defined?(Fiber.scheduler) && Fiber.scheduler
          subscribers.each do |subscriber|
            Fiber.schedule { subscriber.call(message) }
          end
        else
          subscribers.each { |subscriber| subscriber.call(message) }
        end
      end

      def subscribe(topic, &block)
        @subscribers[topic] << block
      end

      def clear!
        @mutex.synchronize do
          @storage.clear
          @subscribers.clear
        end
      end

      def size
        @storage.size
      end

      def topics_count
        @subscribers.size
      end

      def subscribers_count(topic)
        @subscribers[topic].size
      end

      def healthy?
        true
      end
    end
  end
end
