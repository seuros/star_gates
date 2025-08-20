# frozen_string_literal: true

module StarGates
  class Registry
    def initialize
      @gates = {}
      @mutex = Mutex.new
    end

    def register(name, gate)
      @mutex.synchronize do
        @gates[name.to_sym] = gate
      end
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
      @mutex.synchronize do
        @gates.clear
      end
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
