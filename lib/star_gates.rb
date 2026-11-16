# frozen_string_literal: true

require 'zeitwerk'
require 'active_support'
require 'active_support/core_ext/numeric/time'
require 'deadline_machines'
require 'probabilistic_machines'
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
# Defines StarGates.configuration and StarGates.configure, which no constant
# reference would autoload.
require_relative 'star_gates/configuration'

module StarGates
  @registry = Registry.new
  @test_mode = false
  @feature_service = nil

  class << self
    attr_reader :registry

    def flags
      @flags ||= Flags.new
    end

    def define(&)
      context = DSL::DefineContext.new(registry)
      context.instance_eval(&) if block_given?
    end

    # KeyError for a name with no gate.
    def [](name)
      registry.fetch(name)
    end

    # Monotonic Integer nanoseconds: every in-process instant and span.
    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    end

    # Integer nanoseconds since the Unix epoch, for records that outlive the
    # process (event-sourced events).
    def wall_time
      Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
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

    # Forgets every gate and the configured feature service and telemetry
    # adapter, so the next caller starts from nothing.
    def reset!
      registry.clear
      @feature_service = nil
      @telemetry_adapter = nil
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
          circuit: circuit&.to_h,
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
        generated_at: monotonic_time
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
        rollout_percentages.any? ? rollout_percentages.sum.fdiv(rollout_percentages.size).round(2) : 0

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

    # Recent state transitions across all features, newest first, as
    # `{ transitions:, total_found:, limit:, generated_at: }` in both modes;
    # `generated_at` is the monotonic instant. Every transition is
    # `{ feature:, from:, to:, event:, occurred_at: }` in both modes: `feature`
    # the String feature id (the gate name without event sourcing), `from`,
    # `to` and `event` Symbols, `occurred_at` wall-clock Integer nanoseconds.
    # With event sourcing `total_found` counts the transitions the projection
    # keeps; otherwise the registered features' transitions.
    def recent_transitions(limit: 10)
      recent, total = feature_service_enabled? ? projected_transitions(limit) : registered_transitions(limit)
      { transitions: recent, total_found: total, limit: limit, generated_at: monotonic_time }
    end

    def projected_transitions(limit)
      recent = feature_service.recent_transitions(limit: limit).map do |transition|
        transition_entry(transition[:feature_id], transition[:from_state], transition[:to_state],
                         transition[:event_name], transition[:occurred_at])
      end
      [recent, feature_service.transition_count]
    end

    def registered_transitions(limit)
      gates = registry.values.select { |gate| gate.feature.respond_to?(:transition_history) }
      recent = gates.flat_map do |gate|
        gate.feature.transition_history(limit: limit)[:transitions].map { |transition| [gate.name, transition] }
      end
      recent = recent.sort_by { |_, transition| -transition[:at] }.first(limit).map do |name, transition|
        transition_entry(name, transition[:from_state], transition[:to_state], transition[:event],
                         transition[:occurred_at])
      end
      [recent, gates.sum { |gate| gate.feature.transition_count }]
    end

    def transition_entry(feature, from, to, event, occurred_at)
      { feature: feature.to_s, from: from, to: to, event: event, occurred_at: occurred_at }
    end
    private :projected_transitions, :registered_transitions, :transition_entry

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
  end
end

# Percentage shorthand for the feature DSL.
class Numeric
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
