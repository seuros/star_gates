# frozen_string_literal: true

require 'test_helper'

class TestStarGates < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::StarGates::VERSION
  end

  def test_instrumentation_emits_namespaced_events
    events = []
    subscriber = lambda { |name, _start, _finish, _id, payload|
      events << { name: name, payload: payload }
    }

    ActiveSupport::Notifications.subscribed(subscriber, 'star_gates.test') do
      StarGates.instrument('test', feature: 'test_feature')
    end

    assert_equal 1, events.size
    assert_equal 'star_gates.test', events.first[:name]
    assert_equal 'test_feature', events.first[:payload][:feature]
  end

  def test_dsl_basic_gate_definition
    StarGates.define do
      gate :test_gate do
        run { 'success' }
      end
    end

    assert_equal 'success', StarGates[:test_gate].call
  end

  def test_dsl_gate_with_feature_flag
    StarGates.define do
      gate :feature_gate do
        feature rollout: 50.percent
        run { 'feature enabled' }
        fallback { 'feature disabled' }
      end
    end

    result1 = StarGates[:feature_gate].call(key: 1)
    result2 = StarGates[:feature_gate].call(key: 2)

    assert_includes ['feature enabled', 'feature disabled'], result1
    assert_includes ['feature enabled', 'feature disabled'], result2
  end

  def test_dsl_gate_with_circuit_breaker
    call_count = 0
    policy = breaker_policy(2)

    StarGates.define do
      gate :circuit_gate do
        circuit policy
        run do
          call_count += 1
          raise StandardError if call_count <= 3

          'success'
        end
        fallback { 'circuit fallback' }
      end
    end

    gate = StarGates[:circuit_gate]

    assert_equal 'circuit fallback', gate.call
    assert_equal 'circuit fallback', gate.call
    assert_equal 'circuit fallback', gate.call
    assert gate.open?
  end

  def test_runtime_api_gate_access
    StarGates.define do
      gate :api_gate do
        run { 'api response' }
      end
    end

    assert_equal 'api response', StarGates[:api_gate].call
    assert_equal 'api response', StarGates.activate(:api_gate)
  end

  def test_runtime_api_gate_not_found
    assert_raises(KeyError) do
      StarGates[:nonexistent_gate]
    end
  end

  def test_runtime_api_status
    StarGates.define do
      gate :status_gate do
        feature rollout: 100.percent
        run { 'ok' }
      end
    end
    StarGates[:status_gate].feature.enable

    status = StarGates.status(:status_gate)
    assert_equal :status_gate, status[:name]
    assert_equal true, status[:feature_enabled]
    assert_equal false, status[:circuit_open]
  end

  def test_runtime_api_gates_list
    StarGates.define do
      gate :gate1 do
        run { '1' }
      end

      gate :gate2 do
        run { '2' }
      end
    end

    gates = StarGates.gates
    assert_includes gates, :gate1
    assert_includes gates, :gate2
    assert_equal 2, gates.size
  end

  def test_gate_unavailable_without_fallback
    StarGates.define do
      gate :no_fallback_gate do
        feature rollout: 0.percent
        run { 'never runs' }
      end
    end

    assert_raises(StarGates::UnavailableError) do
      StarGates[:no_fallback_gate].call
    end
  end

  def test_gate_context_passing
    StarGates.define do
      gate :context_gate do
        run do |context|
          "Hello #{context[:name]}"
        end
      end
    end

    result = StarGates[:context_gate].call(name: 'World')
    assert_equal 'Hello World', result
  end

  def test_test_mode_functionality
    refute StarGates.test_mode?

    StarGates.test_mode!
    assert StarGates.test_mode?

    StarGates.production_mode!
    refute StarGates.test_mode?
  end

  def test_gate_builder_records_the_declarations
    policy = breaker_policy
    retry_policy = quick_retry
    builder = StarGates::DSL::GateBuilder.new(:built)
    assert_nil builder.circuit_config

    builder.feature(rollout: 10, group: :beta)
    builder.circuit(policy, retry_policy)
    builder.run { :ran }
    builder.fallback { :fallback }

    assert_equal :built, builder.name
    assert_equal({ rollout: 10, group: :beta }, builder.feature_config)
    assert_equal [policy, retry_policy], builder.circuit_config
    gate = builder.build
    assert_same retry_policy, gate.circuit.retry_policy
    assert_same gate.feature, gate.circuit.feature
    assert_equal :ran, builder.run_block.call
    assert_equal :fallback, builder.fallback_block.call
  end

  def test_registry_queries
    registry = StarGates::Registry.new
    assert registry.empty?
    gate = StarGates::Gate.new(:g)
    registry.register('g', gate)

    refute registry.empty?
    assert_same gate, registry['g']
    assert_nil registry[:missing]
    assert_same gate, registry.fetch(:g)
    assert_equal :none, registry.fetch(:missing, :none)
    assert_equal :missing, registry.fetch(:missing) { |name| name }
    assert_raises(KeyError) { registry.fetch(:missing) }
    assert registry.include?(:g)
    assert_equal [:g], registry.keys
    assert_equal [gate], registry.values
    assert_equal 1, registry.size
    assert_equal({ g: gate }, registry.to_h)
    seen = []
    registry.each { |name, _| seen << name }
    assert_equal [:g], seen
    registry.clear
    assert registry.empty?
  end
end
