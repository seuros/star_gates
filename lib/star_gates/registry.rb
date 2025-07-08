# frozen_string_literal: true

require 'concurrent'

module StarGates
  class Registry
    def initialize
      # Use Concurrent::Hash for thread-safe operations (already in dependencies)
      @gates = Concurrent::Hash.new
    end

    def register(name, gate)
      # Concurrent::Hash handles thread-safety automatically
      @gates[name.to_sym] = gate
    end

    def [](name)
      @gates[name.to_sym]
    end

    def fetch(name, default = nil)
      @gates.fetch(name.to_sym, default)
    end

    def include?(name)
      @gates.key?(name.to_sym)
    end

    def keys
      @gates.keys
    end

    def values
      @gates.values
    end

    def each(&)
      @gates.each(&)
    end

    def clear
      # Concurrent::Hash#clear is already thread-safe
      @gates.clear
    end

    def size
      @gates.size
    end

    def empty?
      @gates.empty?
    end

    def to_h
      @gates.dup
    end
  end
end
