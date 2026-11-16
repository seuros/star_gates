# frozen_string_literal: true

require 'test_helper'

class FeatureAggregateTest < Minitest::Test
  Aggregate = StarGates::Hexagonal::FeatureAggregate

  def setup
    super
    @event_store = StarGates::EventStore::EventStore.new
    @repository = StarGates::Hexagonal::FeatureRepository.new(@event_store)
  end

  def created(id = 'checkout')
    Aggregate.new(id).tap { |aggregate| aggregate.create(rollout: 10, group: :beta, metadata: { by: 'ops' }) }
  end

  def test_create_answers_the_event
    aggregate = Aggregate.new('checkout')

    event = aggregate.create(rollout: 10, group: :beta, metadata: {})
    assert_instance_of StarGates::Events::FeatureCreated, event
    assert aggregate.created?
    assert_equal 10, aggregate.rollout_percentage
    assert_equal :beta, aggregate.group_matcher
    assert_equal :disabled, aggregate.current_state
  end

  def test_creating_twice_is_refused_and_changes_nothing
    aggregate = created
    before = aggregate.to_snapshot

    assert_equal :already_created, aggregate.create(rollout: 90)
    assert_equal before, aggregate.to_snapshot
    assert_equal 1, aggregate.uncommitted_events.size
  end

  def test_an_invalid_transition_is_refused_and_changes_nothing
    aggregate = created
    before = aggregate.to_snapshot

    assert_equal :invalid_transition, aggregate.change_state(:disabled, :enabled, :rollout_canary)
    assert_equal before, aggregate.to_snapshot
  end

  # Bug: the transition was checked against the caller's from_state only, so
  # a stale caller could record a transition out of a state the feature was
  # not in.
  def test_a_transition_from_a_state_the_feature_is_not_in_is_refused
    aggregate = created
    aggregate.change_state(:disabled, :enabled, :enable)
    before = aggregate.to_snapshot

    assert_equal :stale_state, aggregate.change_state(:disabled, :canary, :rollout_canary)
    assert_equal before, aggregate.to_snapshot
    assert_equal :enabled, aggregate.current_state
  end

  # Bug: a String to_state was stored as given, so the next transition named
  # with the Symbol answered :stale_state. States and event names are
  # Symbols; a String (or anything else) is a TypeError and changes nothing.
  def test_states_and_event_names_must_be_symbols
    aggregate = created
    before = aggregate.to_snapshot
    pending = aggregate.uncommitted_events.dup

    [%w[disabled canary rollout_canary], [:disabled, 'canary', :rollout_canary],
     [:disabled, :canary, 'rollout_canary']].each do |from, to, event|
      assert_raises(TypeError) { aggregate.change_state(from, to, event) }
      assert_equal before, aggregate.to_snapshot
      assert_equal pending, aggregate.uncommitted_events
    end

    aggregate.change_state(:disabled, :canary, :rollout_canary)
    assert_equal :canary, aggregate.current_state
    assert_instance_of StarGates::Events::FeatureStateChanged, aggregate.change_state(:canary, :enabled, :enable)
  end

  def test_change_state_answers_the_event
    aggregate = created

    event = aggregate.change_state(:disabled, :canary, :rollout_canary, { reason: 'test' })
    assert_instance_of StarGates::Events::FeatureStateChanged, event
    assert_equal :canary, aggregate.current_state
    assert_equal [:canary], aggregate.transition_history.map { |transition| transition[:to_state] }
  end

  def test_records_and_histories
    aggregate = created

    assert_instance_of StarGates::Events::FeatureConfigurationChanged, aggregate.update_configuration(limit: 5)
    assert_instance_of StarGates::Events::FeatureExecuted, aggregate.record_execution({}, :ok, 1_500)
    assert_instance_of StarGates::Events::FeatureEvaluated, aggregate.record_evaluation({}, true, 'ok')
    assert_equal({ limit: 5 }, aggregate.configuration)
    assert_equal [1_500], aggregate.execution_history.map { |execution| execution[:execution_time] }
    assert_equal [true], aggregate.evaluation_history.map { |evaluation| evaluation[:eligible] }
  end

  def test_occurred_at_is_integer_wall_clock_nanoseconds
    aggregate = created

    assert_kind_of Integer, aggregate.uncommitted_events.first.occurred_at
    aggregate.change_state(:disabled, :canary, :rollout_canary)
    assert_kind_of Integer, aggregate.transition_history.first[:occurred_at]
  end

  # Bug: saving left `version` at the replayed count, so the next save with
  # `expected_version: aggregate.version` was refused as a conflict.
  def test_version_follows_saves
    aggregate = created
    assert_equal 1, @repository.save(aggregate, expected_version: aggregate.version)
    assert_equal 1, aggregate.version

    aggregate.change_state(:disabled, :canary, :rollout_canary)
    assert_equal 1, @repository.save(aggregate, expected_version: aggregate.version)
    assert_equal 2, aggregate.version
    assert_empty aggregate.uncommitted_events
  end

  def test_a_conflicting_save_is_refused_and_keeps_the_events
    aggregate = created
    @repository.save(aggregate)
    stale = @repository.find('checkout')
    aggregate.change_state(:disabled, :canary, :rollout_canary)
    @repository.save(aggregate)

    stale.change_state(:disabled, :enabled, :enable)
    assert_equal :version_conflict, @repository.save(stale, expected_version: stale.version)
    assert_equal 1, stale.uncommitted_events.size
    assert_equal 2, @event_store.get_version('checkout')
  end

  def test_saving_nothing_answers_zero
    aggregate = created
    @repository.save(aggregate)

    assert_equal 0, @repository.save(aggregate)
  end

  # Bug: from_snapshot replayed through a private method, so any events
  # since the snapshot raised NoMethodError.
  def test_from_snapshot_replays_later_events
    aggregate = created
    @repository.save(aggregate)
    snapshot = aggregate.to_snapshot
    aggregate.change_state(:disabled, :canary, :rollout_canary)
    later = aggregate.uncommitted_events.dup

    restored = Aggregate.from_snapshot(snapshot, later)
    assert_equal :canary, restored.current_state
    assert_equal 1, restored.transition_history.size
    assert_equal 2, restored.version
    assert_empty restored.uncommitted_events
  end

  def test_repository_find_or_create_and_exists
    refute @repository.exists?('checkout')
    assert_nil @repository.find('checkout')
    refute @repository.find_or_create('checkout').created?

    @repository.save(created)
    assert @repository.exists?('checkout')
    assert @repository.find_or_create('checkout').created?
    assert @repository.healthy?
  end

  def test_mark_events_as_committed_advances_the_version
    aggregate = created
    aggregate.update_configuration(a: 1)

    aggregate.mark_events_as_committed
    assert_equal 2, aggregate.version
    assert_empty aggregate.uncommitted_events
  end

  def test_create_validates_the_rollout
    assert_raises(TypeError) { Aggregate.new('x').create(rollout: '10') }
    assert_raises(RangeError) { Aggregate.new('x').create(rollout: 101) }
  end

  def test_service_queries
    projection = StarGates::Projections::FeatureProjection.new(StarGates::Adapters::MemoryAdapter.new)
    service = StarGates::Hexagonal::FeatureService.new(repository: @repository, projection: projection,
                                                       event_store: @event_store)
    refute service.feature_exists?('checkout')
    assert_nil service.get_feature_aggregate('checkout')

    service.create_feature('checkout', rollout: 5)
    assert service.feature_exists?('checkout')
    assert projection.feature_exists?('checkout')
    assert_equal 5, service.get_feature_aggregate('checkout').rollout_percentage
    assert_same service.create_feature('checkout').id, 'checkout'
  end

  def test_projection_handles_events_directly
    projection = StarGates::Projections::FeatureProjection.new(StarGates::Adapters::MemoryAdapter.new)
    created = StarGates::Events::FeatureCreated.new(aggregate_id: 'p', data: { rollout_percentage: 1 })
    changed = StarGates::Events::FeatureStateChanged.new(aggregate_id: 'p', from_state: :disabled, to_state: :enabled,
                                                         event_name: :enable)
    projection.handle_event(created)
    projection.handle_event(changed)

    assert_equal :enabled, projection.find_feature('p')[:state]
    assert_equal ['p'], projection.find_features_by_state(:enabled).map { |f| f[:id] }
    assert_equal 1, projection.feature_stats[:recent_transitions]
    assert_equal :enable, projection.recent_transitions(limit: 1).first[:event_name]
  end
end
