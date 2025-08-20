# frozen_string_literal: true

require 'test_helper'
require 'json'

class TestJsonRpcApi < Minitest::Test
  def setup
    event_store = StarGates::EventStore::EventStore.new
    repository = StarGates::Hexagonal::FeatureRepository.new(event_store)
    projection = StarGates::Projections::FeatureProjection.new(StarGates::Adapters::MemoryAdapter.new)
    @feature_service = StarGates::Hexagonal::FeatureService.new(
      repository: repository,
      projection: projection,
      event_store: event_store
    )
    @handler = StarGates::JsonRpc::BaseHandler.new(@feature_service)
  end

  def test_create_feature_success
    request = {
      jsonrpc: '2.0',
      method: 'feature.create',
      params: {
        featureId: 'test_feature',
        rollout: 25,
        group: 'beta_users',
        metadata: { team: 'payments' }
      },
      id: 1
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 1, response['id']
    assert response['result']

    result = response['result']
    assert_equal 'test_feature', result['featureId']
    assert result['created']
    assert_equal 'disabled', result['state']
    assert_equal 25, result['rolloutPercentage']
    assert_equal 'beta_users', result['groupMatcher']
  end

  def test_get_feature_success
    # Create feature first
    @feature_service.create_feature('test_feature', rollout: 50)

    request = {
      jsonrpc: '2.0',
      method: 'feature.get',
      params: { featureId: 'test_feature' },
      id: 2
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 2, response['id']
    assert response['result']

    result = response['result']
    assert_equal 'test_feature', result['id']
    assert_equal 'disabled', result['state']
    assert_equal 50, result['rollout_percentage']
  end

  def test_get_nonexistent_feature
    request = {
      jsonrpc: '2.0',
      method: 'feature.get',
      params: { featureId: 'nonexistent' },
      id: 3
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 3, response['id']
    assert response['error']
    assert_equal(-32_000, response['error']['code'])
    assert_includes response['error']['message'], 'Feature not found'
  end

  def test_list_features
    # Create multiple features
    @feature_service.create_feature('feature_1', rollout: 25)
    @feature_service.create_feature('feature_2', rollout: 50)
    @feature_service.change_feature_state('feature_1', :disabled, :enabled, :enable)

    request = {
      jsonrpc: '2.0',
      method: 'feature.list',
      params: {},
      id: 4
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 4, response['id']
    assert response['result']

    features = response['result']['features']
    assert_equal 2, features.size
  end

  def test_list_features_by_state
    @feature_service.create_feature('feature_1')
    @feature_service.create_feature('feature_2')
    @feature_service.change_feature_state('feature_1', :disabled, :enabled, :enable)

    request = {
      jsonrpc: '2.0',
      method: 'feature.list',
      params: { state: 'enabled' },
      id: 5
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert response['result']

    features = response['result']['features']
    assert_equal 1, features.size
    assert_equal 'enabled', features.first['state']
  end

  def test_change_state_success
    @feature_service.create_feature('test_feature')

    request = {
      jsonrpc: '2.0',
      method: 'feature.changeState',
      params: {
        featureId: 'test_feature',
        fromState: 'disabled',
        toState: 'canary',
        event: 'rollout_canary',
        context: { reason: 'testing' }
      },
      id: 6
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 6, response['id']
    assert response['result']

    result = response['result']
    assert_equal 'test_feature', result['featureId']
    assert_equal 'disabled', result['fromState']
    assert_equal 'canary', result['toState']
    assert_equal 'rollout_canary', result['event']
    assert result['success']
  end

  def test_change_state_invalid_transition
    @feature_service.create_feature('test_feature')

    request = {
      jsonrpc: '2.0',
      method: 'feature.changeState',
      params: {
        featureId: 'test_feature',
        fromState: 'disabled',
        toState: 'enabled',
        event: 'invalid_event'
      },
      id: 7
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 7, response['id']
    assert response['error']
    assert_equal(-32_000, response['error']['code'])
    assert_includes response['error']['message'], 'State transition failed'
  end

  def test_feature_stats
    @feature_service.create_feature('feature_1')
    @feature_service.create_feature('feature_2')
    @feature_service.change_feature_state('feature_1', :disabled, :enabled, :enable)

    request = {
      jsonrpc: '2.0',
      method: 'feature.stats',
      params: {},
      id: 8
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 8, response['id']
    assert response['result']

    result = response['result']
    assert_equal 2, result['total_features']
    assert result['by_state']
  end

  def test_recent_transitions
    @feature_service.create_feature('test_feature')
    @feature_service.change_feature_state('test_feature', :disabled, :canary, :rollout_canary)
    @feature_service.change_feature_state('test_feature', :canary, :enabled, :enable)

    request = {
      jsonrpc: '2.0',
      method: 'feature.recentTransitions',
      params: { limit: 5 },
      id: 9
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 9, response['id']
    assert response['result']

    result = response['result']
    assert_equal 2, result['transitions'].size
    assert_equal 5, result['limit']
  end

  def test_system_health
    request = {
      jsonrpc: '2.0',
      method: 'system.health',
      params: {},
      id: 10
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 10, response['id']
    assert response['result']

    result = response['result']
    assert result.key?('healthy')
    assert result['timestamp']
    assert result['version']
  end

  def test_invalid_json
    response = JSON.parse(@handler.handle_request('invalid json'))

    assert_equal '2.0', response['jsonrpc']
    assert response['error']
    assert_equal(-32_700, response['error']['code'])
    assert_equal 'Parse error', response['error']['message']
  end

  def test_invalid_request_format
    request = 'not an object'

    response = JSON.parse(@handler.handle_request(request.to_json))

    assert_equal '2.0', response['jsonrpc']
    assert response['error']
    assert_equal(-32_600, response['error']['code'])
    assert_equal 'Invalid Request', response['error']['message']
  end

  def test_missing_method
    request = {
      jsonrpc: '2.0',
      id: 1
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert response['error']
    assert_equal(-32_600, response['error']['code'])
    assert_includes response['error']['message'], 'missing or invalid method'
  end

  def test_method_not_found
    request = {
      jsonrpc: '2.0',
      method: 'nonexistent.method',
      params: {},
      id: 1
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert response['error']
    assert_equal(-32_601, response['error']['code'])
    assert_includes response['error']['message'], 'Method not found'
  end

  def test_missing_required_params
    request = {
      jsonrpc: '2.0',
      method: 'feature.create',
      params: {}, # Missing featureId
      id: 1
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert response['error']
    assert_equal(-32_602, response['error']['code'])
    assert_includes response['error']['message'], 'Invalid params'
    assert_includes response['error']['message'], 'featureId'
  end

  def test_evaluate_feature
    @feature_service.create_feature('test_feature')

    request = {
      jsonrpc: '2.0',
      method: 'feature.evaluate',
      params: {
        featureId: 'test_feature',
        userContext: { user_id: 123, groups: ['beta'] },
        eligible: true,
        reason: 'User is in beta group'
      },
      id: 11
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 11, response['id']
    assert response['result']

    result = response['result']
    assert_equal 'test_feature', result['featureId']
    assert result['eligible']
    assert_equal 'User is in beta group', result['reason']
    assert result['recordedAt']
  end

  def test_rebuild_projections
    request = {
      jsonrpc: '2.0',
      method: 'system.rebuildProjections',
      params: {},
      id: 12
    }.to_json

    response = JSON.parse(@handler.handle_request(request))

    assert_equal '2.0', response['jsonrpc']
    assert_equal 12, response['id']
    assert response['result']

    result = response['result']
    assert result['success']
    assert result['rebuiltAt']
  end
end
