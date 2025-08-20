# frozen_string_literal: true

module StarGates
  module Adapters
    class BaseAdapter
      def initialize(config = {})
        @config = config
      end

      # Persistence operations
      def store(key, value)
        raise NotImplementedError, 'Subclasses must implement #store'
      end

      def fetch(key)
        raise NotImplementedError, 'Subclasses must implement #fetch'
      end

      def delete(key)
        raise NotImplementedError, 'Subclasses must implement #delete'
      end

      def exists?(key)
        raise NotImplementedError, 'Subclasses must implement #exists?'
      end

      # Caching operations
      def cache_fetch(key, expires_in: nil, &block)
        if exists?(key)
          fetch(key)
        elsif block_given?
          value = block.call
          store(key, value) if value
          value
        end
      end

      def cache_write(key, value, expires_in: nil)
        store(key, value)
      end

      def cache_delete(key)
        delete(key)
      end

      # Messaging operations
      def publish(topic, message)
        # Default no-op implementation
      end

      def subscribe(topic, &)
        # Default no-op implementation
      end

      # Health check
      def healthy?
        true
      end

      protected

      attr_reader :config
    end
  end
end
