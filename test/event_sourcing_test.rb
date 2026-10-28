# frozen_string_literal: true

require 'test_helper'

class TestEventSourcing < Minitest::Test
  def setup
    @event_store = StarGates::EventStore::EventStore.new
    @repository = StarGates::Hexagonal::FeatureRepository.new(@event_store)
    @projection = StarGates::Projections::FeatureProjection.new(StarGates::Adapters::MemoryAdapter.new)
    @feature_service = StarGates::Hexagonal::FeatureService.new(
      repository: @repository,
      projection: @projection,
      event_store: @event_store
    )
  end

  def test_create_feature_generates_events
    feature_id = 'test_feature'

    aggregate = @feature_service.create_feature(feature_id, rollout: 25, group: :beta)

    assert aggregate.created?
    assert_equal feature_id, aggregate.id
    assert_equal :disabled, aggregate.current_state
    assert_equal 25, aggregate.rollout_percentage
    assert_equal :beta, aggregate.group_matcher

    # Check that events were stored
    events = @event_store.get_events(feature_id)
    assert_equal 1, events.size
    assert_instance_of StarGates::Events::FeatureCreated, events.first
  end

  def test_state_transitions_generate_events
    feature_id = 'test_feature'

    # Create feature
    @feature_service.create_feature(feature_id)

    # Change state
    aggregate = @feature_service.change_feature_state(
      feature_id, :disabled, :canary, :rollout_canary, { reason: 'testing' }
    )

    assert_equal :canary, aggregate.current_state

    # Check transition history
    transitions = aggregate.transition_history
    assert_equal 1, transitions.size

    transition = transitions.first
    assert_equal :disabled, transition[:from_state]
    assert_equal :canary, transition[:to_state]
    assert_equal :rollout_canary, transition[:event_name]
    assert_equal({ reason: 'testing' }, transition[:context])

    # Check events in store
    events = @event_store.get_events(feature_id)
    assert_equal 2, events.size
    assert_instance_of StarGates::Events::FeatureStateChanged, events.last
  end

  def test_feature_execution_recording
    feature_id = 'test_feature'

    @feature_service.create_feature(feature_id)

    @feature_service.record_feature_execution(
      feature_id,
      { key: 123 },
      { success: true },
      15.5
    )

    aggregate = @repository.find(feature_id)
    executions = aggregate.execution_history

    assert_equal 1, executions.size
    execution = executions.first
    assert_equal({ key: 123 }, execution[:context])
    assert_equal({ success: true }, execution[:result])
    assert_equal 15.5, execution[:execution_time]
  end

  def test_feature_evaluation_recording
    feature_id = 'test_feature'

    @feature_service.create_feature(feature_id)

    @feature_service.record_feature_evaluation(
      feature_id,
      { key: 123, groups: [:beta] },
      true,
      'Context is in beta group'
    )

    aggregate = @repository.find(feature_id)
    evaluations = aggregate.evaluation_history

    assert_equal 1, evaluations.size
    evaluation = evaluations.first
    assert_equal({ key: 123, groups: [:beta] }, evaluation[:context])
    assert evaluation[:eligible]
    assert_equal 'Context is in beta group', evaluation[:reason]
  end

  def test_projection_updates_with_events
    feature_id = 'test_feature'

    # Create feature
    @feature_service.create_feature(feature_id, rollout: 50)

    # Check projection
    feature_data = @projection.find_feature(feature_id)
    assert feature_data
    assert_equal :disabled, feature_data[:state]
    assert_equal 50, feature_data[:rollout_percentage]

    # Change state
    @feature_service.change_feature_state(feature_id, :disabled, :enabled, :enable)

    # Check projection updated
    updated_feature = @projection.find_feature(feature_id)
    assert_equal :enabled, updated_feature[:state]
    assert_equal 1, updated_feature[:transition_count]
  end

  def test_projection_queries
    # Create multiple features
    @feature_service.create_feature('feature_1', rollout: 25)
    @feature_service.create_feature('feature_2', rollout: 50)
    @feature_service.create_feature('feature_3', rollout: 75)

    # Change some states
    @feature_service.change_feature_state('feature_1', :disabled, :canary, :rollout_canary)
    @feature_service.change_feature_state('feature_2', :disabled, :enabled, :enable)

    # Test queries
    all_features = @projection.all_features
    assert_equal 3, all_features.size

    enabled_features = @projection.find_features_by_state(:enabled)
    assert_equal 1, enabled_features.size
    assert_equal 'feature_2', enabled_features.first[:id]

    canary_features = @projection.find_features_by_state(:canary)
    assert_equal 1, canary_features.size
    assert_equal 'feature_1', canary_features.first[:id]

    disabled_features = @projection.find_features_by_state(:disabled)
    assert_equal 1, disabled_features.size
    assert_equal 'feature_3', disabled_features.first[:id]
  end

  def test_recent_transitions_tracking
    feature_id = 'test_feature'

    @feature_service.create_feature(feature_id)

    # Make several transitions
    @feature_service.change_feature_state(feature_id, :disabled, :canary, :rollout_canary)
    @feature_service.change_feature_state(feature_id, :canary, :enabled, :enable)
    @feature_service.change_feature_state(feature_id, :enabled, :disabled, :disable)

    # Check recent transitions
    recent = @projection.recent_transitions(limit: 5)
    assert_equal 3, recent.size

    # Should be in reverse chronological order
    assert_equal :enabled, recent[0][:from_state]
    assert_equal :disabled, recent[0][:to_state]
    assert_equal :disable, recent[0][:event_name]

    assert_equal :canary, recent[1][:from_state]
    assert_equal :enabled, recent[1][:to_state]
    assert_equal :enable, recent[1][:event_name]
  end

  def test_feature_stats
    @feature_service.create_feature('feature_1')
    @feature_service.create_feature('feature_2')
    @feature_service.create_feature('feature_3')

    @feature_service.change_feature_state('feature_1', :disabled, :enabled, :enable)
    @feature_service.change_feature_state('feature_2', :disabled, :canary, :rollout_canary)

    stats = @projection.feature_stats

    assert_equal 3, stats[:total_features]
    assert_equal 1, stats[:by_state][:disabled]
    assert_equal 1, stats[:by_state][:enabled]
    assert_equal 1, stats[:by_state][:canary]
  end

  def test_rebuild_projections
    # Create some features and transitions
    @feature_service.create_feature('feature_1')
    @feature_service.change_feature_state('feature_1', :disabled, :enabled, :enable)

    # Clear projection
    @projection.clear!

    # Verify projection is empty
    assert_nil @projection.find_feature('feature_1')

    # Rebuild projections
    @feature_service.rebuild_projections!

    # Verify projection is rebuilt
    feature_data = @projection.find_feature('feature_1')
    assert feature_data
    assert_equal :enabled, feature_data[:state]
  end

  def test_invalid_state_transitions
    feature_id = 'test_feature'
    @feature_service.create_feature(feature_id)

    # Try invalid event for valid states
    assert_raises(StarGates::Hexagonal::FeatureAggregate::InvalidTransitionError) do
      @feature_service.change_feature_state(feature_id, :disabled, :enabled, :invalid_event)
    end

    # Try invalid transition (canary -> canary doesn't make sense)
    @feature_service.change_feature_state(feature_id, :disabled, :canary, :rollout_canary)
    assert_raises(StarGates::Hexagonal::FeatureAggregate::InvalidTransitionError) do
      @feature_service.change_feature_state(feature_id, :canary, :canary, :rollout_canary)
    end
  end

  def test_concurrent_updates_with_optimistic_locking
    feature_id = 'test_feature'
    @feature_service.create_feature(feature_id)

    # Simulate concurrent updates
    aggregate1 = @repository.find(feature_id)
    aggregate2 = @repository.find(feature_id)

    # First update succeeds
    aggregate1.change_state(:disabled, :canary, :rollout_canary)
    @repository.save(aggregate1, expected_version: 1)

    # Second update should fail due to version mismatch
    aggregate2.change_state(:disabled, :enabled, :enable)
    assert_raises(StarGates::EventStore::ConcurrencyError) do
      @repository.save(aggregate2, expected_version: 1)
    end
  end

  def test_event_store_health_check
    assert @feature_service.healthy?
  end
end
