# frozen_string_literal: true

require 'test_helper'
require 'open3'

# The StarGates module functions.
class StarGatesModuleTest < Minitest::Test
  # configure_foundation and configure_telemetry set module state that
  # StarGates.reset! keeps; a leaked feature service turns every later
  # test's recent_transitions into the projection's.
  def teardown
    StarGates.reset!
    super
  end

  def define_canary(name, rollout)
    StarGates.define { gate(name) { feature rollout: rollout } }.feature.rollout_canary
  end

  # A library gem must not load Rails: `require 'star_gates'` in a plain
  # process leaves Rails and jsonrpc-rails unloaded and the configuration on
  # the plain-Ruby defaults; the JSON-RPC adapter still autoloads on use.
  def test_requiring_star_gates_loads_no_rails
    script = <<~RUBY
      require 'star_gates'
      abort 'Rails loaded' if defined?(Rails)
      abort 'railties loaded' if $LOADED_FEATURES.any? { |path| path.include?('/railties-') }
      abort 'jsonrpc-rails loaded' if defined?(JSON_RPC)
      puts StarGates.configuration.environment
      puts StarGates::JsonrpcRailsAdapter.available?.inspect
    RUBY
    env = { 'RAILS_ENV' => nil, 'RACK_ENV' => nil, 'RUBY_ENV' => nil }
    output, errors, status = Open3.capture3(env, Gem.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script)

    assert status.success?, "#{output}\n#{errors}"
    assert_equal %w[development nil], output.lines(chomp: true)
  end

  def test_clocks_are_integer_nanoseconds
    first = StarGates.monotonic_time
    assert_kind_of Integer, first
    assert_operator StarGates.monotonic_time, :>=, first

    wall = StarGates.wall_time
    assert_kind_of Integer, wall
    assert_in_delta Time.now.to_r * 1_000_000_000, wall, 5 * 1_000_000_000
  end

  def test_lookup_of_an_unknown_gate_is_a_key_error
    error = assert_raises(KeyError) { StarGates[:missing] }
    assert_equal :missing, error.key
  end

  def test_define_registers_and_answers_the_last_gate
    gate = StarGates.define { gate(:defined) { run { :ran } } }

    assert_same gate, StarGates[:defined]
    assert_equal [:defined], StarGates.gates
    assert_equal :ran, StarGates.activate(:defined)
    assert_equal :defined, StarGates.status(:defined)[:name]
    assert_instance_of StarGates::Registry, StarGates.registry
  end

  # Bug: the average was taken in Integer division before rounding, so
  # rollouts of 10% and 25% averaged 17 instead of 17.5.
  def test_average_rollout_keeps_the_fraction
    define_canary(:ten, 10)
    define_canary(:twenty_five, 25)

    stats = StarGates.rollout_statistics
    assert_in_delta 17.5, stats[:average_rollout]
    assert_equal({ '10-24%' => 1, '25-49%' => 1 }, stats[:rollout_distribution])
    assert_kind_of Integer, stats[:generated_at]
  end

  def test_feature_overview_reports_circuits
    policy = breaker_policy
    StarGates.define do
      gate(:guarded) do
        feature rollout: 0
        circuit policy
      end
    end

    overview = StarGates.feature_overview
    assert_equal 1, overview[:summary][:features_with_circuits]
    assert_equal :closed, overview[:gates][:guarded][:circuit][:state]
  end

  def test_state_distribution
    define_canary(:a, 10)
    StarGates.define { gate(:b) { feature rollout: 0 } }

    distribution = StarGates.state_distribution
    assert_equal 2, distribution[:total]
    assert_in_delta 50.0, distribution[:percentages]['canary']
  end

  def test_recent_transitions_are_newest_first
    define_canary(:first, 10)
    define_canary(:second, 10)

    recent = StarGates.recent_transitions(limit: 1)
    assert_equal 1, recent[:transitions].size
    assert_equal 2, recent[:total_found]
    assert_equal 'second', recent[:transitions].first[:feature]
  end

  # Bug: with event sourcing on the answer was the projection's bare Array,
  # with it off a Hash. Both modes answer the same Hash.
  def test_recent_transitions_have_one_shape_with_event_sourcing
    service = StarGates.configure_foundation
    service.create_feature('checkout')
    service.change_feature_state('checkout', :disabled, :canary, :rollout_canary)
    service.change_feature_state('checkout', :canary, :enabled, :enable)

    recent = StarGates.recent_transitions(limit: 1)
    assert_instance_of Hash, recent
    assert_equal %i[transitions total_found limit generated_at], recent.keys
    assert_equal [1, 2], [recent[:limit], recent[:total_found]]
    assert_equal [:enable], recent[:transitions].map { |transition| transition[:event] }
    assert_kind_of Integer, recent[:generated_at]
  end

  # Bug: event-sourced transitions carried `occurred_at` and `event_name`,
  # in-memory ones `at`, `age` and `event`. Every transition has one shape.
  def test_recent_transition_entries_have_one_shape_in_both_modes
    before = StarGates.wall_time
    define_canary(:checkout, 10)
    in_memory = StarGates.recent_transitions[:transitions].first

    service = StarGates.configure_foundation
    service.create_feature('checkout')
    service.change_feature_state('checkout', :disabled, :canary, :rollout_canary)
    sourced = StarGates.recent_transitions[:transitions].first

    expected = { feature: 'checkout', from: :disabled, to: :canary, event: :rollout_canary }
    [in_memory, sourced].each do |entry|
      assert_equal %i[feature from to event occurred_at], entry.keys
      assert_equal expected, entry.except(:occurred_at)
      assert_kind_of Integer, entry[:occurred_at]
      assert_operator entry[:occurred_at], :>=, before
      assert_operator entry[:occurred_at], :<=, StarGates.wall_time
    end
    assert_equal(in_memory.transform_values(&:class), sourced.transform_values(&:class))
  end

  def test_test_mode_switches
    StarGates.test_mode!
    assert StarGates.test_mode?
    StarGates.production_mode!
    refute StarGates.test_mode?
  end

  def test_instrument_publishes_prefixed_events
    events = []
    ActiveSupport::Notifications.subscribed(->(name, *) { events << name }, 'star_gates.ping') do
      StarGates.instrument('ping', a: 1)
    end
    assert_equal ['star_gates.ping'], events
  end

  def test_foundation_and_telemetry_configuration
    telemetry = Object.new
    service = StarGates.configure_foundation(telemetry: telemetry)

    assert_instance_of StarGates::Hexagonal::FeatureService, service
    assert StarGates.feature_service_enabled?
    assert_same service, StarGates.feature_service
    assert_same telemetry, StarGates.telemetry
    StarGates.enable_event_sourcing!
    assert_same service, StarGates.feature_service

    StarGates.configure_telemetry(nil)
    assert_nil StarGates.telemetry
  end

  def test_flags_are_memoized
    assert_same StarGates.flags, StarGates.flags
  end

  def test_percent_is_identity
    assert_equal 25, 25.percent
  end

  def test_configuration_round_trip
    config = StarGates.configuration
    assert_same config, StarGates.configuration
    StarGates.configure { |c| assert_same config, c }
    assert_kind_of Integer, config.default_timeout
    assert_kind_of Integer, config.cache_ttl
  end
end
