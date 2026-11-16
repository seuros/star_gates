# frozen_string_literal: true

require 'test_helper'

# Execution timing, timeouts and telemetry of ApplicationStarGate.
class ApplicationStarGateRuntimeTest < Minitest::Test
  class RecordingTelemetry < StarGates::Telemetry::TelemetryAdapter
    attr_reader :executions

    def initialize
      super
      @executions = []
    end

    def record_feature_execution(feature_id, state, success, execution_time, context = {})
      executions << { feature_id: feature_id, state: state, success: success, execution_time: execution_time,
                      context: context }
    end

    protected

    def send_metric(*); end
  end

  def setup
    super
    @telemetry = RecordingTelemetry.new
    StarGates.configure_telemetry(@telemetry)
  end

  def teardown
    StarGates.configure_telemetry(nil)
    super
  end

  def feature_class(**options)
    Class.new(StarGates::ApplicationStarGate).tap do |klass|
      klass.configure('runtime_feature', instrumentation: true, performance_monitoring: true, **options)
    end
  end

  # Bug: `!defined?(e)` in the ensure clause is always false, because the
  # rescue variable is a local of the whole method: every execution was
  # reported to telemetry as a failure.
  def test_a_successful_execution_is_reported_as_a_success
    feature = feature_class.new(rollout: 100)
    feature.enable

    assert_equal :ok, feature.execute { :ok }
    assert_equal [true], @telemetry.executions.map { |execution| execution[:success] }
  end

  def test_a_failed_execution_is_reported_as_a_failure
    feature = feature_class.new(rollout: 100)
    feature.enable

    assert_raises(RuntimeError) { feature.execute { raise 'boom' } }
    assert_equal [false], @telemetry.executions.map { |execution| execution[:success] }
  end

  # Bug: the counters were set up only when telemetry was on at construction,
  # so turning it on later made the first timed execution raise NoMethodError
  # on a nil count.
  def test_telemetry_turned_on_after_construction_counts_executions
    StarGates.configure_telemetry(nil)
    feature = feature_class.new(rollout: 100)
    feature.enable
    StarGates.configure_telemetry(@telemetry)

    assert_equal :ok, feature.execute { :ok }
    assert_raises(RuntimeError) { feature.execute { raise 'boom' } }
    assert_equal [2, 50.0], feature.performance_stats.values_at(:total_executions, :error_rate)
  end

  # feature_config is the state-specific configuration; the private copy
  # that nothing called is gone.
  def test_state_specific_configuration_has_one_home
    refute StarGates::ApplicationStarGate.private_method_defined?(:apply_state_specific_config)
    klass = Class.new(StarGates::ApplicationStarGate) do
      configure('stateful', enabled_config: { mode: 'on' }, disabled_config: { mode: 'off' })
    end
    feature = klass.new(rollout: 100)
    assert_equal 'off', feature.feature_config[:mode]
    feature.enable
    assert_equal 'on', feature.feature_config[:mode]
  end

  def test_execution_time_is_integer_nanoseconds
    feature = feature_class.new(rollout: 100)
    feature.enable
    feature.execute { :ok }

    assert_kind_of Integer, @telemetry.executions.first[:execution_time]
  end

  # Bug: a spent budget became Timeout.timeout(0), which Ruby reads as no
  # limit at all, so the block ran unbounded.
  def test_a_zero_timeout_does_not_run_the_block
    feature = feature_class(timeout: 0).new(rollout: 100)
    feature.enable
    ran = false

    error = assert_raises(StarGates::UnavailableError) { feature.execute { ran = true } }
    refute ran
    assert_equal :exceeded, error.refusal
  end

  def test_a_timeout_cuts_the_block_off
    feature = feature_class(timeout: 10_000_000).new(rollout: 100)
    feature.enable

    error = assert_raises(StarGates::UnavailableError) { feature.execute { sleep 1 } }
    assert_equal :exceeded, error.refusal
  end

  def test_no_timeout_runs_the_block
    feature = feature_class.new(rollout: 100)
    feature.enable

    assert_equal :ran, feature.execute { :ran }
  end

  def test_a_float_timeout_is_a_type_error
    feature = feature_class(timeout: 1.0).new(rollout: 100)
    feature.enable

    assert_raises(TypeError) { feature.execute { :ran } }
  end

  def test_the_ambient_deadline_narrows_the_timeout
    feature = feature_class(timeout: 5_000_000_000).new(rollout: 100)
    feature.enable

    error = DeadlineMachines.with_deadline(10_000_000) do
      assert_raises(StarGates::UnavailableError) { feature.execute { sleep 1 } }
    end
    assert_equal :exceeded, error.refusal
  end

  def test_performance_stats_are_integer_nanoseconds
    feature = feature_class.new(rollout: 100)
    feature.enable
    3.times { feature.execute { :ok } }

    stats = feature.performance_stats
    assert_equal 3, stats[:total_executions]
    %i[average_execution_time median_execution_time p95_execution_time p99_execution_time
       last_execution].each { |key| assert_kind_of Integer, stats[key], key }
    assert_in_delta 0.0, stats[:error_rate]
  end

  def test_performance_stats_before_any_execution
    stats = feature_class.new(rollout: 100).performance_stats

    assert_equal 0, stats[:total_executions]
    assert_nil stats[:median_execution_time]
    assert_nil stats[:last_execution]
  end

  def test_preset_timeouts_are_integer_nanoseconds
    critical = Class.new(StarGates::ApplicationStarGate).tap(&:critical_feature).new
    experimental = Class.new(StarGates::ApplicationStarGate).tap(&:experimental_feature).new

    assert_equal 1_000_000_000, critical.timeout
    assert_equal 10_000_000_000, experimental.timeout
  end

  def test_class_with_timeout_sets_nanoseconds
    klass = Class.new(StarGates::ApplicationStarGate)
    klass.with_timeout(250_000_000)

    assert_equal 250_000_000, klass.new.timeout
  end

  # Bug: for_team set the team tag, then configure replaced the tags with
  # the (empty) tag_ options, so the team was always lost.
  def test_for_team_keeps_the_team_tag
    klass = Class.new(StarGates::ApplicationStarGate)
    klass.for_team('payments', tag_tier: 'gold')

    assert_equal({ team: 'payments', tier: 'gold' }, klass.telemetry_tags)
  end

  def test_class_attributes
    klass = Class.new(StarGates::ApplicationStarGate)
    klass.configure('named', tag_tier: 'gold', enabled_config: { mode: 'new' })
    klass.with_circuit_breaker(threshold: 7)
    feature = klass.new

    assert_equal 'named', klass.feature_name
    assert klass.feature_name?
    assert_equal({}, klass.telemetry_tags) # with_circuit_breaker configures again, with no tag_ options
    assert klass.telemetry_tags?
    assert_equal({ enabled: { mode: 'new' } }, klass.state_configs)
    assert klass.state_configs?
    assert_equal 7, klass.options[:circuit_breaker_threshold]
    assert klass.options?
    assert_equal 7, feature.circuit_breaker_threshold
    assert_equal({ enabled: { mode: 'new' } }, feature.state_configs)
    assert feature.state_configs?
    assert_equal 'named', feature.feature_name
    refute_respond_to feature, :feature_name?
    assert feature.telemetry_tags?
  end

  class UnnamedGate < StarGates::ApplicationStarGate; end

  # Reproduces a bug: the `feature_name` class attribute's instance reader
  # replaced Feature#feature_name and answered nil for a gate never given a
  # name, and with it to_h[:name], the summary and the transition history.
  def test_feature_name_falls_back_to_the_class_name_never_nil
    gate = UnnamedGate.new
    gate.enable

    assert_nil UnnamedGate.feature_name
    assert_equal 'UnnamedGate', gate.feature_name
    assert_equal %w[UnnamedGate UnnamedGate UnnamedGate],
                 [gate.to_h[:name], gate.to_h[:feature_name], gate.transition_history[:feature_name]]
    assert_equal "Feature 'UnnamedGate' is ENABLED for all keys (100% rollout).", gate.summary
    assert_equal 'UnnamedFeature', Class.new(StarGates::ApplicationStarGate).new.feature_name

    named = Class.new(StarGates::ApplicationStarGate) { configure('checkout') }.new
    assert_equal %w[checkout checkout], [named.feature_name, named.to_h[:name]]
  end

  # Reproduces a bug: the reported name underscored `self.class.name`, so an
  # anonymous gate raised NoMethodError on nil, and a named but unconfigured
  # one reported 'unnamed_gate' to telemetry while feature_name said
  # 'UnnamedGate'. feature_name is now the only name, used everywhere.
  def test_feature_name_never_raises_and_is_the_only_name
    anonymous = Class.new(StarGates::ApplicationStarGate).new

    assert_equal 'UnnamedFeature', anonymous.feature_name
    assert_equal 'UnnamedGate', UnnamedGate.new.feature_name
    refute_respond_to UnnamedGate.new, :feature_identifier

    named = Class.new(StarGates::ApplicationStarGate) { configure('checkout') }.new
    assert_equal 'checkout', named.feature_name
  end

  def test_class_attribute_writers
    klass = Class.new(StarGates::ApplicationStarGate)
    klass.feature_name = 'written'
    klass.options = { retry_count: 4 }.freeze
    klass.telemetry_tags = { team: 'core' }
    klass.state_configs = { disabled: { mode: 'old' } }
    feature = klass.new
    feature.telemetry_tags = { team: 'mine' }
    feature.state_configs = {}

    assert_equal 'written', klass.feature_name
    assert_equal 4, feature.retry_count
    assert_equal 'old', feature.default_config[:mode]
    assert_equal 'written', feature.feature_name
    refute_respond_to feature, :feature_name=
    assert_equal({ team: 'core' }, klass.telemetry_tags)
    assert_equal({}, feature.state_configs)
  end
end
