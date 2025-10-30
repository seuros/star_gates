# frozen_string_literal: true

require 'zeitwerk'
require 'breaker_machines'
require_relative 'star_gates/errors'
require_relative 'star_gates/dsl'

# Load all foundation modules manually first
require_relative 'star_gates/events/base_event'
require_relative 'star_gates/events/feature_events'
require_relative 'star_gates/event_store/memory_adapter'
require_relative 'star_gates/event_store/event_store'
require_relative 'star_gates/adapters/base_adapter'
require_relative 'star_gates/adapters/memory_adapter'
require_relative 'star_gates/hexagonal/feature_aggregate'
require_relative 'star_gates/hexagonal/feature_repository'
require_relative 'star_gates/projections/feature_projection'
require_relative 'star_gates/hexagonal/feature_service'
require_relative 'star_gates/telemetry/telemetry_adapter'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/star_gates/errors.rb")
loader.ignore("#{__dir__}/star_gates/dsl.rb")
loader.ignore("#{__dir__}/star_gates/events")
loader.ignore("#{__dir__}/star_gates/event_store")
loader.ignore("#{__dir__}/star_gates/adapters")
loader.ignore("#{__dir__}/star_gates/hexagonal")
loader.ignore("#{__dir__}/star_gates/projections")
loader.ignore("#{__dir__}/star_gates/telemetry")
loader.setup

module StarGates
  @registry = Registry.new
  @test_mode = false
  @feature_service = nil

  class << self
    attr_reader :registry

    def define(&)
      context = DSL::DefineContext.new(registry)
      context.instance_eval(&) if block_given?
    end

    def [](name)
      gate = registry[name]
      raise GateNotFoundError, "Gate #{name} not found" unless gate

      gate
    end

    def activate(name, context = {})
      self[name].call(context)
    end

    def status(name)
      self[name].status
    end

    def gates
      registry.keys
    end

    def test_mode!
      @test_mode = true
    end

    def test_mode?
      @test_mode
    end

    def production_mode!
      @test_mode = false
    end

    def reset!
      registry.clear
    end

    # Instrumentation for feature flag events
    def instrument(event, payload = {})
      return unless defined?(ActiveSupport::Notifications)

      ActiveSupport::Notifications.instrument("star_gates.#{event}", payload)
    end

    # ============================================================================
    # SYSTEM-LEVEL INTROSPECTION METHODS
    # ============================================================================

    # Overview of all features and their states
    def feature_overview
      gates = registry.to_h
      overview = {
        total_gates: gates.size,
        gates: {},
        summary: {
          by_status: {},
          total_features: 0,
          features_with_circuits: 0
        }
      }

      gates.each do |name, gate|
        feature = gate.feature
        circuit = gate.circuit

        gate_info = {
          name: name,
          feature: feature&.to_h,
          circuit: circuit ? circuit_info(circuit) : nil,
          status: gate.status
        }

        overview[:gates][name] = gate_info

        # Update summary statistics
        if feature
          overview[:summary][:total_features] += 1
          status = feature.status
          overview[:summary][:by_status][status] = (overview[:summary][:by_status][status] || 0) + 1
        end

        overview[:summary][:features_with_circuits] += 1 if circuit
      end

      overview
    end

    # System-wide rollout statistics
    def rollout_statistics
      gates = registry.to_h
      stats = {
        total_gates: gates.size,
        features_by_status: Hash.new(0),
        average_rollout: 0,
        rollout_distribution: {},
        generated_at: Time.now
      }

      rollout_percentages = []

      gates.each_value do |gate|
        feature = gate.feature
        next unless feature

        status = feature.status
        stats[:features_by_status][status] += 1

        next unless feature.status == 'canary'

        rollout_percentages << feature.rollout_percentage

        range = case feature.rollout_percentage
                when 0...10 then '0-9%'
                when 10...25 then '10-24%'
                when 25...50 then '25-49%'
                when 50...75 then '50-74%'
                when 75...100 then '75-99%'
                else '100%'
                end

        stats[:rollout_distribution][range] = (stats[:rollout_distribution][range] || 0) + 1
      end

      stats[:average_rollout] =
        rollout_percentages.any? ? (rollout_percentages.sum / rollout_percentages.size).round(2) : 0

      stats
    end

    # Distribution of features across states
    def state_distribution
      gates = registry.to_h
      distribution = Hash.new(0)

      gates.each_value do |gate|
        feature = gate.feature
        next unless feature

        distribution[feature.status] += 1
      end

      {
        distribution: distribution,
        total: distribution.values.sum,
        percentages: distribution.transform_values do |count|
          total = distribution.values.sum
          total.positive? ? (count.to_f / total * 100).round(2) : 0
        end
      }
    end

    # Recent state transitions across all features
    def recent_transitions(limit: 10)
      if feature_service_enabled?
        feature_service.recent_transitions(limit: limit)
      else
        # Fallback to legacy implementation
        gates = registry.to_h
        all_transitions = []

        gates.each_value do |gate|
          feature = gate.feature
          next unless feature

          feature_transitions = feature.instance_variable_get(:@transition_history)
          next unless feature_transitions

          all_transitions.concat(feature_transitions.to_a)
        end

        # Sort by timestamp descending and take the most recent
        recent = all_transitions.sort_by { |t| -t[:timestamp].to_f }.first(limit)

        {
          transitions: recent.map do |transition|
            {
              timestamp: transition[:timestamp],
              feature_name: transition[:feature_name],
              feature_class: transition[:feature_class],
              from_state: transition[:from_state],
              to_state: transition[:to_state],
              event: transition[:event],
              duration_since: Time.now - transition[:timestamp]
            }
          end,
          total_found: all_transitions.size,
          limit: limit,
          generated_at: Time.now
        }
      end
    end

    # Configure the foundational architecture
    def configure_foundation(event_store: nil, adapter: nil, telemetry: nil)
      event_store ||= EventStore::EventStore.new
      adapter ||= Adapters::MemoryAdapter.new

      repository = Hexagonal::FeatureRepository.new(event_store)
      projection = Projections::FeatureProjection.new(adapter)

      @feature_service = Hexagonal::FeatureService.new(
        repository: repository,
        projection: projection,
        event_store: event_store
      )

      @telemetry_adapter = telemetry if telemetry

      @feature_service
    end

    # Access to the feature service (lazy initialization)
    def feature_service
      @feature_service ||= configure_foundation
    end

    # Check if feature service is enabled
    def feature_service_enabled?
      !@feature_service.nil?
    end

    # Enable event sourcing mode
    def enable_event_sourcing!
      configure_foundation unless feature_service_enabled?
    end

    # Telemetry integration
    def telemetry
      @telemetry_adapter
    end

    def configure_telemetry(adapter)
      @telemetry_adapter = adapter
    end

    # Check if jsonrpc-rails is available
    def jsonrpc_rails_available?
      defined?(JSON_RPC) && defined?(ActionController::Base)
    end

    private

    def circuit_info(circuit)
      if circuit.respond_to?(:to_h)
        circuit.to_h
      elsif circuit.respond_to?(:stats)
        circuit.stats
      else
        { status: circuit.respond_to?(:status) ? circuit.status : 'unknown' }
      end
    end
  end
end

# Numeric extensions for time helpers
class Numeric
  def seconds
    self
  end
  alias second seconds

  def minutes
    self * 60
  end
  alias minute minutes

  def hours
    self * 3600
  end
  alias hour hours

  def percent
    self
  end
end

# Optional jsonrpc-rails integration
begin
  require 'rails'
  require 'jsonrpc-rails'
  require_relative 'star_gates/jsonrpc_rails_adapter'
rescue LoadError
  # jsonrpc-rails or Rails not available, skip integration
end
