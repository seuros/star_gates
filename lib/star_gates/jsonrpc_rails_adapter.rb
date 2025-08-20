# frozen_string_literal: true

module StarGates
  # Optional JSON-RPC adapter using jsonrpc-rails gem
  # Include this in your Rails controllers when jsonrpc-rails is available
  module JsonrpcRailsAdapter
    def self.available?
      defined?(JSON_RPC) && defined?(ActionController::Base)
    end

    def self.included(base)
      unless available?
        raise LoadError, "jsonrpc-rails gem is required. Add 'gem \"jsonrpc-rails\"' to your Gemfile"
      end
    end

    # Main JSON-RPC request handler
    def process
      if jsonrpc_params_batch?
        # Handle batch requests
        responses = jsonrpc_params.filter_map { |req| handle_single_request(req) }

        if responses.empty?
          head :no_content
        else
          render json: responses.map(&:to_h), status: :ok
        end
      else
        # Handle single request
        response = handle_single_request(jsonrpc_params)

        if response # request (has id)
          render jsonrpc: response.result,
                 id: response.id,
                 error: response.error
        else # notification
          head :no_content
        end
      end
    end

    private

    # Map one JSON_RPC::Request|Notification → Response|nil
    def handle_single_request(req)
      # Notifications have id == nil. Return nil = no response.
      return nil if req.id.nil?

      result_or_error = dispatch_method(req.method, req.params || {})
      build_response(req.id, result_or_error)
    end

    # Dispatch JSON-RPC method to appropriate handler
    def dispatch_method(method, params)
      case method
      when 'feature.create'
        create_feature(params)
      when 'feature.get'
        get_feature(params)
      when 'feature.list'
        list_features(params)
      when 'feature.changeState'
        change_state(params)
      when 'feature.execute'
        execute_feature(params)
      when 'feature.evaluate'
        evaluate_feature(params)
      when 'feature.stats'
        feature_stats(params)
      when 'feature.recentTransitions'
        recent_transitions(params)
      when 'system.health'
        system_health(params)
      when 'system.rebuildProjections'
        rebuild_projections(params)
      else
        JSON_RPC::JsonRpcError.build(:method_not_found)
      end
    end

    # Feature management methods
    def create_feature(params)
      validate_required_params(params, ['featureId'])

      feature_id = params['featureId']
      rollout = params['rollout'] || 0
      group = params['group']
      metadata = params['metadata'] || {}

      aggregate = feature_service.create_feature(feature_id, rollout: rollout, group: group, metadata: metadata)

      {
        featureId: aggregate.id,
        created: aggregate.created?,
        state: aggregate.current_state,
        rolloutPercentage: aggregate.rollout_percentage,
        groupMatcher: aggregate.group_matcher
      }
    rescue => e
      JSON_RPC::JsonRpcError.build(:invalid_params, data: { error: e.message })
    end

    def get_feature(params)
      validate_required_params(params, ['featureId'])

      feature = feature_service.find_feature(params['featureId'])
      return JSON_RPC::JsonRpcError.build(:invalid_params, data: { error: 'Feature not found' }) unless feature

      feature
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    def list_features(params)
      state = params['state']

      features = if state
                   feature_service.find_features_by_state(state.to_sym)
                 else
                   feature_service.all_features
                 end

      { features: features }
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    def change_state(params)
      validate_required_params(params, %w[featureId fromState toState event])

      feature_id = params['featureId']
      from_state = params['fromState'].to_sym
      to_state = params['toState'].to_sym
      event_name = params['event'].to_sym
      context = params['context'] || {}

      aggregate = feature_service.change_feature_state(feature_id, from_state, to_state, event_name, context)

      {
        featureId: aggregate.id,
        fromState: from_state,
        toState: to_state,
        event: event_name,
        success: true
      }
    rescue => e
      JSON_RPC::JsonRpcError.build(:invalid_params, data: { error: "State transition failed: #{e.message}" })
    end

    def execute_feature(params)
      validate_required_params(params, ['featureId'])

      feature_id = params['featureId']
      context = params['context'] || {}

      start_time = Time.now
      result = yield if block_given? # Allow caller to provide execution block
      execution_time = ((Time.now - start_time) * 1000).round(2) # ms

      feature_service.record_feature_execution(feature_id, context, result, execution_time)

      {
        featureId: feature_id,
        result: result,
        executionTime: execution_time,
        context: context
      }
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    def evaluate_feature(params)
      validate_required_params(params, %w[featureId userContext])

      feature_id = params['featureId']
      user_context = params['userContext']
      eligible = params['eligible'] || false
      reason = params['reason'] || 'No reason provided'

      feature_service.record_feature_evaluation(feature_id, user_context, eligible, reason)

      {
        featureId: feature_id,
        userContext: user_context,
        eligible: eligible,
        reason: reason,
        recordedAt: Time.now.utc.iso8601
      }
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    def feature_stats(_params)
      feature_service.feature_stats
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    def recent_transitions(params)
      limit = params['limit'] || 10

      {
        transitions: feature_service.recent_transitions(limit: limit),
        limit: limit
      }
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    def system_health(_params)
      {
        healthy: feature_service.healthy?,
        timestamp: Time.now.utc.iso8601,
        version: StarGates::VERSION
      }
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    def rebuild_projections(_params)
      feature_service.rebuild_projections!

      {
        success: true,
        rebuiltAt: Time.now.utc.iso8601
      }
    rescue => e
      JSON_RPC::JsonRpcError.build(:internal_error, data: { error: e.message })
    end

    # Helper methods
    def validate_required_params(params, required_keys)
      missing_keys = required_keys - params.keys
      return if missing_keys.empty?

      raise ArgumentError, "Missing required parameters: #{missing_keys.join(', ')}"
    end

    def build_response(id, outcome)
      if outcome.is_a?(JSON_RPC::JsonRpcError)
        JSON_RPC::Response.new(id: id, error: outcome)
      else
        JSON_RPC::Response.new(id: id, result: outcome)
      end
    end

    def feature_service
      @feature_service ||= StarGates.feature_service
    end
  end
end
