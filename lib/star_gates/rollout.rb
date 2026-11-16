# frozen_string_literal: true

module StarGates
  # The rollout percentage rule shared by Feature and the event-sourced
  # FeatureAggregate.
  module Rollout
    # The rollout itself: TypeError unless an Integer, RangeError outside 0..100.
    def self.validated(rollout)
      raise TypeError, "rollout must be an Integer percentage, got #{rollout.inspect}" unless rollout.is_a?(Integer)
      raise RangeError, "rollout must be in 0..100, got #{rollout}" unless (0..100).cover?(rollout)

      rollout
    end
  end
end
