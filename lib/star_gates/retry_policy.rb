# frozen_string_literal: true

require 'chrono_machines'

module StarGates
  # How a circuit retries a failed call: a chrono_machines strategy
  # (Exponential, Constant or Fibonacci; spans in Integer nanoseconds) and an
  # attempt budget that counts the first try (1..255, or nil for unbounded).
  # The fields and their order are ChronoMachines::Retry's.
  #
  # Validated when built, by chrono's core: TypeError for the wrong type,
  # RangeError for a budget outside 1..255.
  RetryPolicy = Data.define(:strategy, :max_attempts) do
    def initialize(strategy:, max_attempts:)
      ChronoMachines::Retry.new(strategy, max_attempts)
      super
    end
  end

  # Sealed like the sibling values: `initialize` is where it validates.
  RetryPolicy.singleton_class.undef_method(:allocate)
  RetryPolicy.define_singleton_method(:inherited) { |_| raise TypeError, "#{RetryPolicy} cannot be subclassed" }
end
