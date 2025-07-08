# frozen_string_literal: true

require "zeitwerk"
require "breaker_machines"

loader = Zeitwerk::Loader.for_gem
loader.setup

module StarGates
  class Error < StandardError; end
  
  # DSL entry point for defining star gates
  def self.define(&block)
    # Implementation will be added later
    raise NotImplementedError, "StarGates.define is not yet implemented"
  end
end
