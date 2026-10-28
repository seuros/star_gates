# frozen_string_literal: true

require_relative '../test_helper'

class ApplicationStarGatesControllerTest < ActionDispatch::IntegrationTest
  test 'should get application star gates index' do
    get '/application_star_gates'
    assert_response :success

    json_response = JSON.parse(response.body)
    assert json_response['application_features']
    assert json_response['total_count']

    # Should have our demo features
    feature_names = json_response['application_features'].map { |f| f['name'] }
    assert_includes feature_names, 'demo_payment_processing'
    assert_includes feature_names, 'demo_notification_system'
    assert_includes feature_names, 'demo_ai_recommendations'
  end

  test 'should get introspection for payment feature' do
    get '/application_star_gates/demo_payment_processing/introspection'
    assert_response :success

    json_response = JSON.parse(response.body)
    assert json_response['introspection']
    assert json_response['configuration_summary']
    assert json_response['performance_stats']
    assert json_response['feature_identifier']
    assert_equal 'demo_payment_processing', json_response['feature_identifier']
  end

  test 'should execute application star gate feature' do
    post '/application_star_gates/demo_payment_processing/transition', params: { event: 'enable' }
    assert_response :success

    post '/application_star_gates/demo_payment_processing/execute',
         params: { context: { key: 123 }, test_payload: 'test execution' }
    assert_response :success

    json_response = JSON.parse(response.body)
    assert json_response['result']
    assert json_response['execution_time_ms']
    assert json_response['performance_stats']
    assert_equal 'test execution', json_response['result']
  end

  test 'should transition feature state' do
    post '/application_star_gates/demo_notification_system/transition',
         params: { event: 'enable' }
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_equal 'enable', json_response['event']
    assert_equal 'enabled', json_response['new_status']
    assert json_response['transitioned_at']
  end

  test 'should handle invalid transition event' do
    post '/application_star_gates/demo_ai_recommendations/transition',
         params: { event: 'invalid_event' }
    assert_response :bad_request

    json_response = JSON.parse(response.body)
    assert json_response['error']
  end

  test 'should handle feature not found' do
    get '/application_star_gates/nonexistent_feature/introspection'
    assert_response :not_found

    json_response = JSON.parse(response.body)
    assert json_response['error']
  end
end
