# frozen_string_literal: true

module StarGates
  class Error < StandardError; end
  class UnavailableError < Error; end
  class GateNotFoundError < Error; end
  class InvalidConfigurationError < Error; end
end
