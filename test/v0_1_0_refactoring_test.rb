# frozen_string_literal: true

require 'test_helper'
require 'yaml'
require 'tempfile'

# Tests for v0.1.0 refactoring and bug fixes
# Tests all critical fixes, security patches, and new features
class V010RefactoringTest < Minitest::Test
  # ============================================================================
  # CRITICAL BUG FIX: parse_rollout dead code
  # ============================================================================

  def test_parse_rollout_percentage_string
    feature = StarGates::Feature.new(rollout: '50%')

    # The bug was: empty conditional block for '%' check
    # Before fix: '50%' would parse incorrectly
    # After fix: properly strips % and converts to integer
    assert_equal 50, feature.rollout_percentage
  end

  def test_parse_rollout_percentage_string_various_formats
    {
      '25%' => 25,
      '75%' => 75,
      '100%' => 100,
      '0%' => 0,
      '50' => 50,     # without %
      50 => 50,       # numeric
      100.0 => 100    # float
    }.each do |input, expected|
      feature = StarGates::Feature.new(rollout: input)
      assert_equal expected, feature.rollout_percentage,
                   "Failed to parse rollout: #{input.inspect}"
    end
  end

  def test_parse_rollout_edge_cases
    # Invalid inputs should default to 0
    assert_equal 0, StarGates::Feature.new(rollout: nil).rollout_percentage
    assert_equal 0, StarGates::Feature.new(rollout: '').rollout_percentage
    assert_equal 0, StarGates::Feature.new(rollout: 'invalid').rollout_percentage
  end

  # ============================================================================
  # SECURITY FIX: YAML safe_load_file
  # ============================================================================

  def test_yaml_configuration_safe_load
    # Create temporary YAML config file
    Tempfile.create(['star_gates_config', '.yml']) do |file|
      file.write(<<~YAML)
        development:
          instrumentation: true
          default_timeout: 10.0
          log_level: :debug
      YAML
      file.rewind

      config = StarGates::Configuration.new
      config.load_from_file(file.path)

      assert_equal true, config.instrumentation
      assert_equal 10.0, config.default_timeout
      assert_equal :debug, config.log_level
    end
  end

  def test_yaml_configuration_rejects_unsafe_content
    skip 'YAML.safe_load_file not available' unless YAML.respond_to?(:safe_load_file)

    # Attempt to load YAML with arbitrary code execution
    Tempfile.create(['malicious_config', '.yml']) do |file|
      file.write(<<~YAML)
        development:
          instrumentation: !ruby/object:Gem::Requirement
            requirements: []
      YAML
      file.rewind

      config = StarGates::Configuration.new

      # safe_load_file should raise or handle safely
      assert_raises(Psych::DisallowedClass, StandardError) do
        config.load_from_file(file.path)
      end
    end
  end

  # ============================================================================
  # RUBY 3.3+ FEATURE: Data.define instead of OpenStruct
  # ============================================================================

  def test_feature_mock_user_with_data_define
    skip 'Data.define not available (Ruby < 3.2)' unless defined?(Data)

    feature = StarGates::Feature.new(rollout: 50)
    feature.rollout_canary

    # simulate_for_user should use Data.define internally
    result = feature.simulate_for_user(user_id: 123, user_groups: [:beta])

    assert result.is_a?(Hash)
    assert_equal 123, result[:user_id]
    assert_equal [:beta], result[:user_groups]
    assert_includes [true, false], result[:eligible]
  end

  def test_feature_mock_user_responds_to_id_and_groups
    skip 'Data.define not available (Ruby < 3.2)' unless defined?(Data)

    feature = StarGates::Feature.new(group: :beta)
    feature.rollout_canary

    # Internal MockUser should behave like a struct
    result = feature.simulate_for_user(user_id: 456, user_groups: %i[beta admin])

    # User should be eligible for beta group
    assert result[:eligible], 'User with beta group should be eligible'
  end

  # ============================================================================
  # PERFORMANCE: Concurrent::Hash in Registry
  # ============================================================================

  def test_registry_thread_safety_with_concurrent_hash
    registry = StarGates::Registry.new

    # Simulate concurrent writes
    threads = 10.times.map do |i|
      Thread.new do
        100.times do |j|
          gate_name = :"gate_#{i}_#{j}"
          gate = StarGates::Gate.new(gate_name)
          registry.register(gate_name, gate)
        end
      end
    end

    threads.each(&:join)

    # Should have 1000 gates registered without race conditions
    assert_equal 1000, registry.size
  end

  def test_registry_concurrent_reads_and_writes
    registry = StarGates::Registry.new
    gate = StarGates::Gate.new(:test_gate)
    registry.register(:test_gate, gate)

    # Simulate concurrent reads and writes
    read_count = Concurrent::AtomicFixnum.new(0)
    write_count = Concurrent::AtomicFixnum.new(0)

    threads = []

    # Reader threads
    5.times do
      threads << Thread.new do
        100.times do
          value = registry[:test_gate]
          read_count.increment if value
        end
      end
    end

    # Writer threads
    5.times do |i|
      threads << Thread.new do
        100.times do |j|
          new_gate = StarGates::Gate.new(:"concurrent_gate_#{i}_#{j}")
          registry.register(:"concurrent_gate_#{i}_#{j}", new_gate)
          write_count.increment
        end
      end
    end

    threads.each(&:join)

    # All reads should succeed
    assert_equal 500, read_count.value

    # All writes should succeed
    assert_equal 500, write_count.value

    # Total gates: original + 500 new ones
    assert_equal 501, registry.size
  end

  # ============================================================================
  # NEW FEATURE: ChronoMachines retry integration
  # ============================================================================

  def test_circuit_without_retry_policy
    circuit = StarGates::Circuit.new(threshold: 2, within: 30)

    # Should work without retry policy (backward compatible)
    result = circuit.call { 'success' }
    assert_equal 'success', result
  end

  def test_circuit_with_retry_policy_success_after_retries
    call_count = 0
    circuit = StarGates::Circuit.new(
      threshold: 5,
      within: 30,
      retry_config: {
        max_attempts: 3,
        base_delay: 0.001 # Fast for tests
      }
    )

    # Fails twice, succeeds on third attempt
    result = circuit.call do
      call_count += 1
      raise StandardError, 'temporary failure' if call_count < 3

      'success'
    end

    assert_equal 'success', result
    assert_equal 3, call_count, 'Should retry twice before succeeding'
  end

  def test_circuit_with_retry_policy_exhausted
    call_count = 0
    circuit = StarGates::Circuit.new(
      threshold: 5,
      within: 30,
      retry_config: {
        max_attempts: 3,
        base_delay: 0.001
      }
    )

    # Always fails - should exhaust retries
    error = assert_raises(StandardError) do
      circuit.call do
        call_count += 1
        raise StandardError, 'persistent failure'
      end
    end

    assert_equal 'persistent failure', error.message
    assert_equal 3, call_count, 'Should attempt 3 times before giving up'
  end

  def test_circuit_retry_instrumentation
    instrumentation_events = []

    # Capture instrumentation events
    subscriber = lambda { |name, _start, _finish, _id, payload|
      instrumentation_events << { name: name, payload: payload }
    }

    begin
      ActiveSupport::Notifications.subscribe('star_gates.circuit.retry', &subscriber)

      call_count = 0
      circuit = StarGates::Circuit.new(
        threshold: 5,
        within: 30,
        retry_config: {
          max_attempts: 3,
          base_delay: 0.001
        }
      )

      # Fail once, then succeed
      circuit.call do
        call_count += 1
        raise StandardError, 'temporary' if call_count == 1

        'success'
      end

      # Should have instrumented the retry
      assert instrumentation_events.size >= 1, 'Should emit circuit.retry event'

      retry_event = instrumentation_events.find { |e| e[:name] == 'star_gates.circuit.retry' }
      assert retry_event, 'Should have circuit.retry event'
      assert_equal 'StandardError', retry_event[:payload][:exception]
      assert_equal 1, retry_event[:payload][:attempt]
    ensure
      ActiveSupport::Notifications.unsubscribe('star_gates.circuit.retry')
    end
  end

  # ============================================================================
  # REFACTORING: Simplified time parsing
  # ============================================================================

  def test_circuit_time_parsing_with_numeric_extensions
    # Should work with Numeric extensions (1.minute, 30.seconds)
    circuit = StarGates::Circuit.new(
      threshold: 3,
      within: 2.minutes,
      reset_after: 5.minutes
    )

    assert_equal 120, circuit.within
    assert_equal 300, circuit.reset_after
  end

  def test_circuit_time_parsing_with_activesupport_duration
    skip 'ActiveSupport::Duration not available' unless defined?(ActiveSupport::Duration)

    duration = ActiveSupport::Duration.build(90) # 90 seconds
    circuit = StarGates::Circuit.new(
      threshold: 3,
      within: duration,
      reset_after: 2.minutes
    )

    assert_equal 90, circuit.within
    assert_equal 120, circuit.reset_after
  end

  def test_circuit_time_parsing_with_plain_integers
    # Should work with plain integers (backward compatible)
    circuit = StarGates::Circuit.new(
      threshold: 3,
      within: 60,
      reset_after: 120
    )

    assert_equal 60, circuit.within
    assert_equal 120, circuit.reset_after
  end

  # ============================================================================
  # INTEGRATION: Full stack test with all fixes
  # ============================================================================

  def test_full_stack_integration_with_all_fixes
    # Test that all fixes work together
    StarGates.reset!

    StarGates.define do
      gate :payment_processor do
        feature rollout: '75%', group: :premium # Test parse_rollout fix

        circuit threshold: 3,
                within: 1.minute,
                reset_after: 30.seconds,
                retry_config: { # Test ChronoMachines integration
                  max_attempts: 3,
                  base_delay: 0.001
                }

        run { 'payment processed' }
        fallback { 'payment queued' }
      end
    end

    gate = StarGates[:payment_processor]

    # Gate should exist
    assert gate, 'Gate should be registered'

    # Feature should parse 75% correctly (bug fix)
    assert_equal 75, gate.feature.rollout_percentage

    # Circuit should have retry policy (new feature)
    assert gate.circuit.retry_policy, 'Circuit should have retry policy'

    # Should work end-to-end
    gate.feature.rollout_canary
    premium_user = MockUser.new(1, [:premium])

    result = gate.call(user: premium_user)
    assert_includes ['payment processed', 'payment queued'], result
  end
end
