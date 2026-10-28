# frozen_string_literal: true

require_relative '../test_helper'

class FeaturesControllerTest < ActionDispatch::IntegrationTest
  test 'should get features index' do
    get '/features'
    assert_response :success

    json_response = JSON.parse(response.body)
    assert json_response['features']
    assert json_response['statistics']
    assert json_response['state_distribution']
  end

  test 'should get feature details' do
    # First create a feature gate to test with
    StarGates.define do
      gate :test_feature do
        feature rollout: 50
      end
    end

    get '/features/test_feature'
    assert_response :success

    json_response = JSON.parse(response.body)
    assert json_response['feature']
    assert json_response['gate_status']
    assert json_response['introspection']
  end

  test 'should handle feature not found' do
    get '/features/nonexistent_feature'
    assert_response :not_found

    json_response = JSON.parse(response.body)
    assert json_response['error']
  end

  test 'should activate feature' do
    StarGates.define do
      gate :activatable_feature do
        feature rollout: 100
        run { 'activated' }
      end
    end
    StarGates[:activatable_feature].feature.enable

    post '/features/activatable_feature/activate', params: { context: { key: 123 } }
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_equal 'activatable_feature', json_response['feature']
    assert json_response['activated_at']
  end

  test 'should get recent transitions' do
    get '/features/recent_transitions'
    assert_response :success

    json_response = JSON.parse(response.body)
    assert json_response['transitions']
    assert json_response['total_found']
  end
end
