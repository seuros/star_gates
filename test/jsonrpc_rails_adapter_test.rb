# frozen_string_literal: true

require 'test_helper'
require 'action_controller'

# Stand-ins for what jsonrpc-rails provides, so the adapter runs without it.
unless defined?(JSON_RPC)
  module JSON_RPC
    class JsonRpcError < StandardError
      attr_reader :code, :message, :data

      def initialize(code, message, data = nil)
        super(message)
        @code = code
        @message = message
        @data = data
      end

      def self.build(type, data: nil)
        case type
        when :method_not_found
          new(-32_601, 'Method not found', data)
        when :invalid_params
          new(-32_602, 'Invalid params', data)
        when :internal_error
          new(-32_603, 'Internal error', data)
        else
          new(-32_000, 'Unknown error', data)
        end
      end
    end

    class Response
      attr_reader :id, :result, :error

      def initialize(id:, result: nil, error: nil)
        @id = id
        @result = result
        @error = error
      end

      def to_h
        hash = { id: @id }
        hash[:result] = @result if @result
        hash[:error] = @error if @error
        hash
      end
    end

    class MockRequest
      attr_reader :id, :method, :params

      def initialize(id, method, params)
        @id = id
        @method = method
        @params = params
      end
    end
  end
end

require 'star_gates/jsonrpc_rails_adapter'

class MockController
    include StarGates::JsonrpcRailsAdapter

  attr_accessor :rendered_json, :rendered_jsonrpc, :rendered_id, :rendered_error, :status_code

  def initialize
    @rendered_json = nil
    @rendered_jsonrpc = nil
    @rendered_id = nil
    @rendered_error = nil
    @status_code = nil
  end

  # Mock Rails controller methods
  def render(options = {})
    if options[:json]
      @rendered_json = options[:json]
      @status_code = options[:status]
    elsif options.key?(:jsonrpc)
      @rendered_jsonrpc = options[:jsonrpc]
      @rendered_id = options[:id]
      @rendered_error = options[:error]
    end
  end

  def head(status)
    @status_code = status
  end

  # Mock jsonrpc_params methods (these would be provided by jsonrpc-rails)
  def jsonrpc_params
    @mock_request
  end

  def jsonrpc_params_batch?
    @mock_request.is_a?(Array)
  end

  def set_mock_request(request)
    @mock_request = request
  end
end

class JsonrpcRailsAdapterTest < Minitest::Test
  # A fresh feature service per test, dropped after: StarGates.reset! keeps
  # it, so features would carry over between tests and files.
  def setup
    StarGates.reset!
    StarGates.configure_foundation
    @controller = MockController.new
  end

  def teardown
    StarGates.reset!
  end

  def test_single_request_success
    request = JSON_RPC::MockRequest.new(1, 'system.health', {})
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 1, @controller.rendered_id
    assert @controller.rendered_jsonrpc
    assert @controller.rendered_jsonrpc[:healthy]
    assert @controller.rendered_jsonrpc[:version]
    assert_nil @controller.rendered_error
  end

  def test_single_request_method_not_found
    request = JSON_RPC::MockRequest.new(2, 'unknown.method', {})
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 2, @controller.rendered_id
    assert_nil @controller.rendered_jsonrpc
    assert @controller.rendered_error
    assert_equal(-32_601, @controller.rendered_error.code)
    assert_equal('Method not found', @controller.rendered_error.message)
  end

  def test_notification_request
    request = JSON_RPC::MockRequest.new(nil, 'system.health', {})
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal :no_content, @controller.status_code
  end

  def test_batch_request
    requests = [
      JSON_RPC::MockRequest.new(1, 'system.health', {}),
      JSON_RPC::MockRequest.new(2, 'feature.stats', {})
    ]
    @controller.set_mock_request(requests)

    @controller.handle_jsonrpc

    assert @controller.rendered_json
    assert_equal 2, @controller.rendered_json.size
    assert_equal :ok, @controller.status_code
  end

  def test_batch_request_with_notifications_only
    requests = [
      JSON_RPC::MockRequest.new(nil, 'system.health', {}),
      JSON_RPC::MockRequest.new(nil, 'feature.stats', {})
    ]
    @controller.set_mock_request(requests)

    @controller.handle_jsonrpc

    assert_equal :no_content, @controller.status_code
  end

  def test_feature_create_success
    request = JSON_RPC::MockRequest.new(1, 'feature.create', {
                                          'featureId' => 'test_feature',
                                          'rollout' => 25,
                                          'group' => 'beta'
                                        })
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 1, @controller.rendered_id
    result = @controller.rendered_jsonrpc
    assert_equal 'test_feature', result[:featureId]
    assert_equal 25, result[:rolloutPercentage]
    assert_equal 'beta', result[:groupMatcher]
  end

  def test_feature_create_missing_params
    request = JSON_RPC::MockRequest.new(1, 'feature.create', {})
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 1, @controller.rendered_id
    assert @controller.rendered_error
    assert_equal(-32_602, @controller.rendered_error.code)
  end

  def test_feature_get_success
    # First create a feature
    StarGates.feature_service.create_feature('test_feature', rollout: 50)

    request = JSON_RPC::MockRequest.new(1, 'feature.get', {
                                          'featureId' => 'test_feature'
                                        })
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 1, @controller.rendered_id
    assert @controller.rendered_jsonrpc
    assert_nil @controller.rendered_error
  end

  def test_feature_get_not_found
    request = JSON_RPC::MockRequest.new(1, 'feature.get', {
                                          'featureId' => 'nonexistent'
                                        })
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 1, @controller.rendered_id
    assert @controller.rendered_error
    assert_includes @controller.rendered_error.data[:error], 'not found'
  end

  def test_feature_list
    # Create some features
    StarGates.feature_service.create_feature('feature1', rollout: 25)
    StarGates.feature_service.create_feature('feature2', rollout: 75)

    request = JSON_RPC::MockRequest.new(1, 'feature.list', {})
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 1, @controller.rendered_id
    result = @controller.rendered_jsonrpc
    assert result[:features]
    assert result[:features].size >= 2
  end

  def test_change_state_success
    # Create a feature first
    StarGates.feature_service.create_feature('test_feature', rollout: 50)

    request = JSON_RPC::MockRequest.new(1, 'feature.changeState', {
                                          'featureId' => 'test_feature',
                                          'fromState' => 'disabled',
                                          'toState' => 'canary',
                                          'event' => 'rollout_canary'
                                        })
    @controller.set_mock_request(request)

    @controller.handle_jsonrpc

    assert_equal 1, @controller.rendered_id
    result = @controller.rendered_jsonrpc
    assert_equal 'test_feature', result[:featureId]
    assert_equal :disabled, result[:fromState]
    assert_equal :canary, result[:toState]
    assert result[:success]
  end

  def test_a_refused_change_answers_its_refusal
    StarGates.feature_service.create_feature('test_feature', rollout: 50)
    @controller.set_mock_request(JSON_RPC::MockRequest.new(1, 'feature.changeState', {
                                                             'featureId' => 'test_feature', 'fromState' => 'enabled',
                                                             'toState' => 'disabled', 'event' => 'disable'
                                                           }))
    @controller.handle_jsonrpc

    assert_equal(-32_602, @controller.rendered_error.code)
    assert_equal 'stale_state', @controller.rendered_error.data[:error]
  end

  def test_recording_for_a_missing_feature_answers_not_found
    @controller.set_mock_request(JSON_RPC::MockRequest.new(1, 'feature.evaluate', {
                                                             'featureId' => 'ghost', 'context' => {}
                                                           }))
    @controller.handle_jsonrpc

    assert_equal 'not_found', @controller.rendered_error.data[:error]
  end

  def test_execution_time_is_integer_nanoseconds
    StarGates.feature_service.create_feature('test_feature')
    @controller.set_mock_request(JSON_RPC::MockRequest.new(1, 'feature.execute', { 'featureId' => 'test_feature' }))
    @controller.handle_jsonrpc

    assert_kind_of Integer, @controller.rendered_jsonrpc[:executionTime]
  end

  def test_available
    assert StarGates::JsonrpcRailsAdapter.available?
  end

  # A controller's superclass owns `process(action, *args)` (Rails dispatch).
  class ControllerLike
    attr_reader :dispatched

    def process(action, *args)
      @dispatched = [action, *args]
      public_send(action)
    end
  end

  # Bug: the adapter defined a zero-argument `process`, which sat between a
  # controller and its superclass and replaced Rails' dispatch: every request
  # raised ArgumentError before reaching an action.
  def test_including_the_adapter_keeps_the_controllers_process
    controller = Class.new(ControllerLike) do
      include StarGates::JsonrpcRailsAdapter

      attr_accessor :rendered

      def jsonrpc_params = JSON_RPC::MockRequest.new(7, 'system.health', {})
      def jsonrpc_params_batch? = false
      def render(options) = self.rendered = options
    end.new

    controller.process(:handle_jsonrpc)
    assert_equal [:handle_jsonrpc], controller.dispatched
    assert_equal 7, controller.rendered[:id]
    assert controller.rendered[:jsonrpc][:healthy]
  end

  def test_the_adapter_overrides_no_action_controller_method
    adapter = StarGates::JsonrpcRailsAdapter
    mine = adapter.instance_methods(false) + adapter.private_instance_methods(false)
    rails = ActionController::Base.instance_methods + ActionController::Base.private_instance_methods
    assert_empty mine & rails
  end
end
