# frozen_string_literal: true

require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/string/inflections'
require 'active_support/concern'
require 'active_support/notifications'
require_relative 'configuration'

module StarGates
  class ApplicationStarGate < Feature
    # The configured name; nil until `configure(name)`. Instances answer
    # #feature_name, which falls back to the class name, never nil.
    class_attribute :feature_name, instance_accessor: false
    class_attribute :options, default: {}.freeze, instance_accessor: false
    class_attribute :telemetry_tags, default: {}
    class_attribute :state_configs, default: {}

    def initialize(rollout: nil, group: nil, **options)
      # Use ActiveSupport::HashWithIndifferentAccess for better key handling
      @instance_config = ActiveSupport::HashWithIndifferentAccess.new(options)

      # Merge with class-level config using deep_merge
      @merged_config = self.class.options.with_indifferent_access.deep_merge(@instance_config)

      # Use configuration defaults if not provided
      rollout ||= @merged_config[:default_rollout] || 0
      group ||= @merged_config[:default_group]

      super(rollout: rollout, group: group)

      # Initialize state-specific configurations using HashWithIndifferentAccess
      @feature_config = ActiveSupport::HashWithIndifferentAccess.new(state_configs[:enabled] || {})
      @default_config = ActiveSupport::HashWithIndifferentAccess.new(state_configs[:disabled] || {})
      @canary_config = ActiveSupport::HashWithIndifferentAccess.new(state_configs[:canary] || {})

      # Counters exist whatever telemetry says now: it is read per call and
      # may be turned on after construction.
      setup_counters
    end

    # Enhanced state-specific methods with instrumentation and telemetry
    def execute(context = {}, &block)
      instrument_execution(context) do
        super(context) do
          if block_given?
            with_timeout(@merged_config[:timeout], &block)
          else
            true
          end
        end
      end
    end

    def ui_component(context = {})
      instrument_ui_access(context) do
        super(context)
      end
    end

    def config_value(key, context = {})
      instrument_config_access(key, context) do
        super(key, context)
      end
    end

    def timeout
      @merged_config[:timeout]
    end

    def retry_count
      @merged_config[:retry_count]
    end

    def circuit_breaker_threshold
      @merged_config[:circuit_breaker_threshold]
    end

    def cache_ttl
      @merged_config[:cache_ttl]
    end

    # Public method for checking performance monitoring status
    def performance_monitoring_enabled?
      @merged_config[:performance_monitoring]
    end

    # Public method for configuration summary
    def configuration_summary
      {
        timeout: timeout,
        retry_count: retry_count,
        circuit_breaker_threshold: circuit_breaker_threshold,
        cache_ttl: cache_ttl,
        telemetry_enabled: telemetry_enabled?,
        performance_monitoring: performance_monitoring_enabled?,
        error_reporting: error_reporting_enabled?
      }
    end

    # The configured name, else Feature's (the class name).
    def feature_name = self.class.feature_name || super

    # Feature-specific configuration with state awareness
    def feature_config
      case status
      when 'enabled'
        @feature_config
      when 'canary'
        @canary_config.any? ? @canary_config : @feature_config
      else
        @default_config
      end
    end

    attr_reader :default_config

    # Performance monitoring
    def performance_stats
      return {} unless performance_monitoring_enabled?

      {
        average_execution_time: average_execution_time,
        median_execution_time: latency_quantile(0.5),
        p95_execution_time: latency_quantile(0.95),
        p99_execution_time: latency_quantile(0.99),
        total_executions: @execution_count,
        error_rate: calculate_error_rate,
        last_execution: @last_execution_time
      }
    end

    # Enhanced introspection with application-specific data
    def to_h
      base_data = super
      base_data.merge(
        configuration: configuration_summary,
        performance: performance_stats,
        environment: StarGates.configuration.environment,
        feature_name: feature_name
      )
    end

    class << self
      def configure(name = nil, **options)
        self.feature_name = name if name

        # Extract state-specific configs
        state_specific = extract_state_configs(options)
        self.state_configs = state_specific[:states] if state_specific[:states].any?

        # Extract telemetry tags
        self.telemetry_tags = extract_telemetry_tags(options)

        self.options = self.options.merge(options.except(*state_specific[:extracted_keys])).freeze
      end

      # `timeout` in Integer nanoseconds.
      def with_timeout(timeout, **options)
        configure(timeout: timeout, **options)
      end

      def with_circuit_breaker(threshold: 5, **options)
        configure(circuit_breaker_threshold: threshold, **options)
      end

      def for_team(team_name, **options)
        configure(**options)
        self.telemetry_tags = { team: team_name }.merge(telemetry_tags)
      end

      def critical_feature(**options)
        configure(
          timeout: 1_000_000_000,
          retry_count: 5,
          circuit_breaker_threshold: 10,
          performance_monitoring: true,
          **options
        )
      end

      def experimental_feature(**options)
        configure(
          timeout: 10_000_000_000,
          retry_count: 1,
          performance_monitoring: true,
          **options
        )
      end

      private

      def extract_state_configs(options)
        state_keys = %i[enabled_config disabled_config canary_config]
        extracted = {}

        state_keys.each do |key|
          if options.key?(key)
            state_name = key.to_s.sub('_config', '').to_sym
            extracted[state_name] = options[key]
          end
        end

        {
          states: extracted,
          extracted_keys: state_keys
        }
      end

      def extract_telemetry_tags(options)
        options.select { |k, _| k.to_s.start_with?('tag_') }
               .transform_keys { |k| k.to_s.sub(/^tag_/, '').to_sym }
      end
    end

    private

    def telemetry_enabled?
      @merged_config[:instrumentation] && StarGates.telemetry
    end

    def error_reporting_enabled?
      @merged_config[:error_reporting]
    end

    def setup_counters
      @execution_count = 0
      @error_count = 0
      @last_execution_time = nil
    end

    def instrument_execution(context)
      return yield unless telemetry_enabled?

      ActiveSupport::Notifications.instrument('star_gates.feature.execute',
                                              feature: feature_name, status: status,
                                              context: context) do |payload|
        timed_execution(payload, context) { yield }
      end
    end

    # Times the block in monotonic Integer nanoseconds and reports it whether
    # it returns or raises.
    def timed_execution(payload, context)
      started = StarGates.monotonic_time
      succeeded = false
      begin
        result = yield
        succeeded = true
        result
      rescue StandardError => e
        payload[:error] = e.class.name
        raise
      ensure
        execution_time = StarGates.monotonic_time - started
        succeeded ? record_successful_execution(execution_time) : record_failed_execution(execution_time)
        payload[:success] = succeeded
        payload[:execution_time] = execution_time
        StarGates.telemetry&.record_feature_execution(feature_name, status, succeeded, execution_time, context)
      end
    end

    def instrument_ui_access(context)
      return yield unless telemetry_enabled?

      # Use ActiveSupport::Notifications for UI access tracking
      ActiveSupport::Notifications.instrument('star_gates.ui_component.access',
                                              feature: feature_name,
                                              context: context) do |payload|
        result = yield
        payload[:component] = result

        StarGates.telemetry&.record_counter(
          'star_gates.ui_component.access',
          1,
          tags: telemetry_tags.merge(component: result, feature: feature_name)
        )

        result
      end
    end

    def instrument_config_access(key, context)
      return yield unless telemetry_enabled?

      # Use ActiveSupport::Notifications for config access tracking
      ActiveSupport::Notifications.instrument('star_gates.config.access',
                                              feature: feature_name,
                                              config_key: key,
                                              context: context) do |payload|
        result = yield
        payload[:config_value] = result

        StarGates.telemetry&.record_counter(
          'star_gates.config.access',
          1,
          tags: telemetry_tags.merge(config_key: key, feature: feature_name)
        )

        result
      end
    end

    # Runs the block within `timeout` Integer nanoseconds (nil: no limit of
    # its own), narrowed by the ambient deadline. A budget already spent does
    # not run the block: Timeout.timeout(0) would mean no limit at all.
    def with_timeout(timeout, &)
      DeadlineMachines.check!
      budget = timeout.nil? ? DeadlineMachines.remaining : DeadlineMachines.clamp_sleep(timeout)
      return yield if budget.nil?
      raise timed_out(budget) unless budget.positive?

      DeadlineMachines.with_deadline(budget) { Timeout.timeout(Rational(budget, NS_PER_SECOND), &) }
    rescue Timeout::Error
      raise timed_out(budget)
    end

    def timed_out(budget)
      UnavailableError.new(feature_name, :exceeded, "Feature #{feature_name} timed out after #{budget}ns")
    end

    def record_successful_execution(duration)
      record_execution(duration)
    end

    def record_failed_execution(duration)
      return unless performance_monitoring_enabled?

      @error_count += 1
      record_execution(duration)
    end

    # Cluster budget for the latency digest; error is about one part in this.
    LATENCY_COMPRESSION = 100
    NS_PER_SECOND = 1_000_000_000
    private_constant :LATENCY_COMPRESSION, :NS_PER_SECOND

    def record_execution(duration)
      return unless performance_monitoring_enabled?

      latency.add(duration)
      @latency_total = latency_total + duration
      @execution_count += 1
      @last_execution_time = StarGates.monotonic_time
    end

    def average_execution_time
      return if @execution_count.zero?

      latency_total / @execution_count
    end

    # A latency quantile in Integer nanoseconds, nil before any execution.
    def latency_quantile(quantile)
      return if @execution_count.zero?

      latency.quantile(quantile).round
    end

    # Telemetry and performance monitoring are separate switches, so the digest
    # is built where it is used rather than in either setup path.
    def latency
      @latency ||= ProbabilisticMachines::TDigest.new(LATENCY_COMPRESSION)
    end

    def latency_total
      @latency_total ||= 0
    end

    def calculate_error_rate
      return 0 if @execution_count.zero?

      (@error_count.to_f / @execution_count * 100).round(2)
    end

    def telemetry_tags
      base_tags = {
        feature: feature_name,
        state: status,
        environment: StarGates.configuration.environment
      }

      class_tags = self.class.telemetry_tags || {}
      base_tags.merge(class_tags)
    end
  end
end
