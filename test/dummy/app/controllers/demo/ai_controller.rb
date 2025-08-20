# frozen_string_literal: true

class Demo::AiController < ApplicationController
  before_action :setup_ai_feature

  def recommendations
    user_id = params[:user_id] || 'user_456'
    context = params[:context] || {}

    result = @ai_feature.get_recommendations(user_id, context)

    render json: {
      recommendations: result,
      feature_status: @ai_feature.status,
      ai_model: @ai_feature.feature_config['ai_model'],
      performance_stats: @ai_feature.performance_stats
    }
  end

  def analyze_behavior
    user_id = params[:user_id] || 'user_789'
    actions = params[:actions] || []

    result = @ai_feature.analyze_user_behavior(user_id, actions)

    render json: {
      analysis: result,
      feature_status: @ai_feature.status,
      features_enabled: @ai_feature.feature_config['features']
    }
  end

  private

  def setup_ai_feature
    @ai_feature = DemoExperimentalFeature.new(rollout: 10)

    # Set state based on params for testing
    case params[:state]
    when 'enabled'
      @ai_feature.enable
    when 'canary'
      @ai_feature.rollout_canary
    when 'disabled'
      @ai_feature.disable
    end
  end
end
