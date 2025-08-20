# frozen_string_literal: true

require 'json'
require 'securerandom'

module StarGates
  module JsonRpc
    class BaseHandler
      JSONRPC_VERSION = '2.0'

      def initialize(feature_service)
        @feature_service = feature_service
      end

      def handle_request(request_body)
        request = parse_request(request_body)
        validate_request(request)

        result = dispatch_method(request['method'], request['params'] || {})

        success_response(request['id'], result)
      rescue JsonRpcError => e
        id = request.is_a?(Hash) ? request['id'] : nil
        error_response(id, e.code, e.message, e.data)
      rescue StandardError => e
        id = request.is_a?(Hash) ? request['id'] : nil
        error_response(id, -32_603, "Internal error: #{e.message}")
      end

      private

      def parse_request(body)
        JSON.parse(body)
      rescue JSON::ParserError
        raise JsonRpcError.new(-32_700, 'Parse error')
      end

      def validate_request(request)
        raise JsonRpcError.new(-32_600, 'Invalid Request') unless request.is_a?(Hash)

        unless request['jsonrpc'] == JSONRPC_VERSION
          raise JsonRpcError.new(-32_600, 'Invalid Request: missing or invalid jsonrpc version')
        end

        unless request['method'].is_a?(String)
          raise JsonRpcError.new(-32_600, 'Invalid Request: missing or invalid method')
        end

        # ID can be string, number, or null, but must be present for requests (not notifications)
        return if request.key?('id')

        raise JsonRpcError.new(-32_600, 'Invalid Request: missing id')
      end

      def dispatch_method(method, params)
        case method
        when 'feature.create'
          handle_create_feature(params)
        when 'feature.get'
          handle_get_feature(params)
        when 'feature.list'
          handle_list_features(params)
        when 'feature.changeState'
          handle_change_state(params)
        when 'feature.execute'
          handle_execute_feature(params)
        when 'feature.evaluate'
          handle_evaluate_feature(params)
        when 'feature.stats'
          handle_feature_stats(params)
        when 'feature.recentTransitions'
          handle_recent_transitions(params)
        when 'system.health'
          handle_system_health(params)
        when 'system.rebuildProjections'
          handle_rebuild_projections(params)
        else
          raise JsonRpcError.new(-32_601, "Method not found: #{method}")
        end
      end

      def handle_create_feature(params)
        validate_required_params(params, ['featureId'])

        feature_id = params['featureId']
        rollout = params['rollout'] || 0
        group = params['group']
        metadata = params['metadata'] || {}

        aggregate = @feature_service.create_feature(feature_id, rollout: rollout, group: group, metadata: metadata)

        {
          featureId: aggregate.id,
          created: aggregate.created?,
          state: aggregate.current_state,
          rolloutPercentage: aggregate.rollout_percentage,
          groupMatcher: aggregate.group_matcher
        }
      end

      def handle_get_feature(params)
        validate_required_params(params, ['featureId'])

        feature = @feature_service.find_feature(params['featureId'])
        raise JsonRpcError.new(-32_000, 'Feature not found') unless feature

        feature
      end

      def handle_list_features(params)
        state = params['state']

        features = if state
                     @feature_service.find_features_by_state(state.to_sym)
                   else
                     @feature_service.all_features
                   end

        { features: features }
      end

      def handle_change_state(params)
        validate_required_params(params, %w[featureId fromState toState event])

        feature_id = params['featureId']
        from_state = params['fromState'].to_sym
        to_state = params['toState'].to_sym
        event_name = params['event'].to_sym
        context = params['context'] || {}

        begin
          aggregate = @feature_service.change_feature_state(feature_id, from_state, to_state, event_name, context)

          {
            featureId: aggregate.id,
            fromState: from_state,
            toState: to_state,
            event: event_name,
            success: true
          }
        rescue StandardError => e
          raise JsonRpcError.new(-32_000, "State transition failed: #{e.message}")
        end
      end

      def handle_execute_feature(params)
        validate_required_params(params, ['featureId'])

        feature_id = params['featureId']
        context = params['context'] || {}

        start_time = Time.now
        result = yield if block_given? # Allow caller to provide execution block
        execution_time = ((Time.now - start_time) * 1000).round(2) # ms

        @feature_service.record_feature_execution(feature_id, context, result, execution_time)

        {
          featureId: feature_id,
          result: result,
          executionTime: execution_time,
          context: context
        }
      end

      def handle_evaluate_feature(params)
        validate_required_params(params, %w[featureId userContext])

        feature_id = params['featureId']
        user_context = params['userContext']
        eligible = params['eligible'] || false
        reason = params['reason'] || 'No reason provided'

        @feature_service.record_feature_evaluation(feature_id, user_context, eligible, reason)

        {
          featureId: feature_id,
          userContext: user_context,
          eligible: eligible,
          reason: reason,
          recordedAt: Time.now.utc.iso8601
        }
      end

      def handle_feature_stats(_params)
        @feature_service.feature_stats
      end

      def handle_recent_transitions(params)
        limit = params['limit'] || 10

        {
          transitions: @feature_service.recent_transitions(limit: limit),
          limit: limit
        }
      end

      def handle_system_health(_params)
        {
          healthy: @feature_service.healthy?,
          timestamp: Time.now.utc.iso8601,
          version: StarGates::VERSION
        }
      end

      def handle_rebuild_projections(_params)
        @feature_service.rebuild_projections!

        {
          success: true,
          rebuiltAt: Time.now.utc.iso8601
        }
      end

      def validate_required_params(params, required_keys)
        missing_keys = required_keys - params.keys
        return if missing_keys.empty?

        raise JsonRpcError.new(-32_602, "Invalid params: missing #{missing_keys.join(', ')}")
      end

      def success_response(id, result)
        {
          jsonrpc: JSONRPC_VERSION,
          result: result,
          id: id
        }.to_json
      end

      def error_response(id, code, message, data = nil)
        error = {
          code: code,
          message: message
        }
        error[:data] = data if data

        {
          jsonrpc: JSONRPC_VERSION,
          error: error,
          id: id
        }.to_json
      end

      attr_reader :feature_service
    end

    class JsonRpcError < StandardError
      attr_reader :code, :data

      def initialize(code, message, data = nil)
        super(message)
        @code = code
        @data = data
      end
    end
  end
end
