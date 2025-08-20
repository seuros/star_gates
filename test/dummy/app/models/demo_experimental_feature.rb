# frozen_string_literal: true

class DemoExperimentalFeature < StarGates::ApplicationStarGate
  configure 'demo_ai_recommendations',
            timeout: 5.0,
            retry_count: 1,
            circuit_breaker_threshold: 3,
            performance_monitoring: true,
            instrumentation: true,
            enabled_config: {
              ai_model: 'gpt-4',
              max_recommendations: 10,
              confidence_threshold: 0.8,
              real_time_learning: true,
              features: %w[contextual_analysis user_behavior_tracking a_b_testing]
            },
            canary_config: {
              ai_model: 'gpt-3.5',
              max_recommendations: 5,
              confidence_threshold: 0.9,
              real_time_learning: false,
              features: ['contextual_analysis']
            },
            disabled_config: {
              ai_model: 'rule_based',
              max_recommendations: 3,
              confidence_threshold: 1.0,
              real_time_learning: false,
              features: []
            }

  experimental_feature # Uses the class method for experimental features

  def get_recommendations(user_id, _context = {})
    config = feature_config

    execute do
      # Simulate AI processing time based on model
      sleep_time = case config['ai_model']
                   when 'gpt-4' then 0.1
                   when 'gpt-3.5' then 0.05
                   else 0.01
                   end
      sleep(sleep_time)

      recommendations = generate_mock_recommendations(config['max_recommendations'])

      {
        success: true,
        user_id: user_id,
        recommendations: recommendations,
        ai_model: config['ai_model'],
        confidence_threshold: config['confidence_threshold'],
        features_used: config['features'],
        real_time_learning: config['real_time_learning'],
        generated_at: Time.current,
        processing_time_ms: (sleep_time * 1000).round(2)
      }
    end
  end

  def analyze_user_behavior(user_id, actions)
    config = feature_config

    return nil unless config['features'].include?('user_behavior_tracking')

    execute do
      {
        user_id: user_id,
        actions_analyzed: actions.size,
        patterns_detected: rand(3..7),
        confidence_score: rand(0.6..0.95).round(2),
        ai_model: config['ai_model'],
        analyzed_at: Time.current
      }
    end
  end

  private

  def generate_mock_recommendations(max_count)
    items = ['Product A', 'Service B', 'Feature C', 'Option D', 'Choice E',
             'Alternative F', 'Solution G', 'Method H', 'Approach I', 'Strategy J']

    items.sample(max_count).map.with_index do |item, index|
      {
        id: "rec_#{index + 1}",
        title: item,
        confidence: rand(0.7..0.95).round(2),
        reason: "Based on AI analysis using #{feature_config['ai_model']}"
      }
    end
  end
end
