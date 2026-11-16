# frozen_string_literal: true

require 'test_helper'

class EventStoreTest < Minitest::Test
  def setup
    super
    @store = StarGates::EventStore::EventStore.new
  end

  def event(id = 'checkout', changes = {})
    StarGates::Events::FeatureConfigurationChanged.new(aggregate_id: id, configuration_changes: changes)
  end

  def test_append_versions_and_reads
    assert_equal 2, @store.append('checkout', [event, event])
    assert_equal 0, @store.append('checkout', [])
    assert_equal 2, @store.get_version('checkout')
    assert_equal [2], @store.get_events('checkout', from_version: 1).map(&:version)
  end

  def test_queries_by_time_and_type
    before = StarGates.wall_time
    @store.append('a', [event('a')])
    @store.append('b', [StarGates::Events::FeatureCreated.new(aggregate_id: 'b')])

    assert_equal %w[b a], @store.get_events_from(before).map(&:aggregate_id)
    assert_empty @store.get_events_from(StarGates.wall_time + 1_000_000_000)
    assert_equal ['b'], @store.get_events_by_type('FeatureCreated').map(&:aggregate_id)
  end

  def test_subscribers_and_replay
    seen = []
    typed = []
    @store.subscribe { |e| seen << e.aggregate_id }
    @store.subscribe('FeatureCreated') { |e| typed << e.aggregate_id }
    @store.append('a', [event('a')])
    @store.append('b', [StarGates::Events::FeatureCreated.new(aggregate_id: 'b')])

    assert_equal %w[a b], seen
    assert_equal ['b'], typed
    replayed = []
    @store.replay_all { |e| replayed << e.aggregate_id }
    assert_equal %w[a b], replayed
  end

  def test_memory_adapter_counts_and_clears
    adapter = StarGates::EventStore::MemoryAdapter.new
    assert adapter.append('a', [event('a')])
    refute adapter.append('a', [event('a')], 0)
    assert adapter.append('b', [event('b')], 0)

    assert_equal 2, adapter.size
    assert_equal 2, adapter.aggregate_count
    assert_equal ['a'], adapter.get_events('a').map(&:aggregate_id)
    assert_equal 2, adapter.get_events_from(0).size
    assert_equal 2, adapter.get_events_by_type('FeatureConfigurationChanged').size
    replayed = []
    adapter.replay_all { |e| replayed << e.aggregate_id }
    assert_equal %w[a b], replayed
    adapter.clear!
    assert_equal 0, adapter.size
    assert_equal 0, adapter.get_version('a')
  end

  def test_events_are_frozen_values_identified_by_id
    one = event
    other = event

    assert_predicate one, :frozen?
    assert_equal 'FeatureConfigurationChanged', one.event_type
    assert_match(/\A\h{8}-/, one.event_id)
    assert_equal one, one.dup
    refute_equal one, other
    assert_equal one.event_id.hash, one.hash
    assert_kind_of Integer, one.occurred_at
    assert_equal one.occurred_at, one.to_h[:occurred_at]
    assert_equal 'star_gates', one.metadata[:source]
  end

  def test_event_readers
    changed = StarGates::Events::FeatureStateChanged.new(aggregate_id: 'a', from_state: :disabled, to_state: :enabled,
                                                         event_name: :enable, context: { by: 'ops' })
    executed = StarGates::Events::FeatureExecuted.new(aggregate_id: 'a', context: {}, result: :ok,
                                                      execution_time: 1_000)
    evaluated = StarGates::Events::FeatureEvaluated.new(aggregate_id: 'a', context: {}, eligible: true, reason: 'r')
    registered = StarGates::Events::GateRegistered.new(aggregate_id: 'a', gate_name: :g, feature_class: 'F')

    assert_equal [:disabled, :enabled, :enable, { by: 'ops' }],
                 [changed.from_state, changed.to_state, changed.event_name, changed.context]
    assert_equal [{}, :ok, 1_000], [executed.context, executed.result, executed.execution_time]
    assert_equal [{}, true, 'r'], [evaluated.context, evaluated.eligible, evaluated.reason]
    assert_equal [:g, 'F'], [registered.gate_name, registered.feature_class]
    assert_equal 'SystemReset', StarGates::Events::SystemReset.new(aggregate_id: 'a').event_type
  end
end
