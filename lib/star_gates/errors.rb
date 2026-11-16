# frozen_string_literal: true

module StarGates
  class Error < StandardError; end

  # A gate answered without running its primary path and had no fallback.
  # `refusal` says why: :ineligible (the feature is off for this context),
  # :failed (the primary raised; it is the `cause`), :exceeded (the time
  # budget ran out), or the circuit's own refusal symbol (:open, :busy,
  # :full), carried whole from breaker_machines.
  class UnavailableError < Error
    attr_reader :gate, :refusal

    def initialize(gate, refusal, message = nil)
      @gate = gate
      @refusal = refusal
      super(message || "#{gate} is unavailable (#{refusal})")
    end
  end
end
