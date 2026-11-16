# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'star_gates'

require 'minitest/autorun'

# Breaker policies and retry policies for the tests, in Integer nanoseconds.
module PolicyHelpers
  NS_PER_SECOND = 1_000_000_000

  def seconds(count) = count * NS_PER_SECOND

  # Opens after `threshold` failures within `within`, cools down for
  # `reset_after`, closes on the first half-open success.
  def breaker_policy(threshold = 5, within: seconds(30), reset_after: seconds(60))
    BreakerMachines::Policy.new(BreakerMachines::Threshold.new(threshold, nil, 0), within,
                                BreakerMachines::Recovery.new(reset_after, 0.0, 1, 1), nil)
  end

  # Up to `max_attempts` tries with a microsecond constant backoff.
  def quick_retry(max_attempts = 3)
    StarGates::RetryPolicy.new(ChronoMachines::Constant.new(1_000, 0.0), max_attempts)
  end
end

class Minitest::Test
  include PolicyHelpers

  def setup
    StarGates.reset!
  end

  def teardown
    StarGates.reset!
  end
end
