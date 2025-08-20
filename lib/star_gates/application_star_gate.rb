# frozen_string_literal: true

require 'active_support/configurable'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/concern'
require 'active_support/notifications'
require_relative 'configuration'

module StarGates
  class ApplicationStarGate < Feature
    include ActiveSupport::Configurable

    # Use ActiveSupport class attributes instead of custom implementation
    class_attribute :feature_name
    class_attribute :telemetry_tags, default: {}
    class_attribute :state_configs, default: {}

    def initialize(rollout: nil, group: nil, **options)
      # Use ActiveSupport::HashWithIndifferentAccess for better key handling
      @instance_config = ActiveSupport::HashWithIndifferentAccess.new(options)

      # Merge with class-level config using deep_merge
      @merged_config = self.class.config.to_h.with_indifferent_access.deep_merge(@instance_config)

      # Use configuration defaults if not provided
      rollout ||= @merged_config[:default_rollout] || 0
      group ||= @merged_config[:default_group]

      super(rollout: rollout, group: group)

      # Initialize state-specific configurations using HashWithIndifferentAccess
      @feature_config = ActiveSupport::HashWithIndifferentAccess.new(state_configs[:enabled] || {})
      @default_config = ActiveSupport::HashWithIndifferentAccess.new(state_configs[:disabled] || {})
      @canary_config = ActiveSupport::HashWithIndifferentAccess.new(state_configs[:canary] || {})

      # Setup telemetry if enabled
      setup_telemetry if telemetry_enabled?

      # Setup error handling
      setup_error_handling if error_reporting_enabled?
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

    # Configuration access using ActiveSupport::Configurable
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

    # Public method to get feature identifier
    def feature_identifier
      self.class.feature_name || self.class.name.demodulize.underscore
    end

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
        average_execution_time: @execution_times&.sum&./([@execution_times.size, 1].max) || 0,
        total_executions: @execution_count || 0,
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
        feature_name: self.class.feature_name || feature_name
      )
    end

    # Class methods for configuration using ActiveSupport::Configurable
    class << self
      def configure(name = nil, **options)
        self.feature_name = name if name

        # Extract state-specific configs
        state_specific = extract_state_configs(options)
        self.state_configs = state_specific[:states] if state_specific[:states].any?

        # Extract telemetry tags
        self.telemetry_tags = extract_telemetry_tags(options)

        # Set configuration using ActiveSupport::Configurable
        remaining_options = options.except(*state_specific[:extracted_keys])
        remaining_options.each do |key, value|
          config.send("#{key}=", value)
        end
      end

      def with_timeout(seconds, **options)
        configure(timeout: seconds, **options)
      end

      def with_circuit_breaker(threshold: 5, **options)
        configure(circuit_breaker_threshold: threshold, **options)
      end

      def for_team(team_name, **options)
        self.telemetry_tags = { team: team_name }
        configure(**options)
      end

      def critical_feature(**options)
        configure(
          timeout: 1.0,
          retry_count: 5,
          circuit_breaker_threshold: 10,
          performance_monitoring: true,
          **options
        )
      end

      def experimental_feature(**options)
        configure(
          timeout: 10.0,
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

    def setup_telemetry
      @execution_times = []
      @execution_count = 0
      @error_count = 0
      @last_execution_time = nil
    end

    def setup_error_handling
      # Setup error tracking and reporting
    end

    def instrument_execution(context)
      return yield unless telemetry_enabled?

      # Use ActiveSupport::Notifications for instrumentation
      ActiveSupport::Notifications.instrument('star_gates.feature.execute',
                                              feature: feature_identifier,
                                              status: status,
                                              context: context) do |payload|
        start_time = Time.now
        begin
          result = yield
          execution_time = Time.now - start_time
          record_successful_execution(execution_time)

          payload[:success] = true
          payload[:execution_time_ms] = (execution_time * 1000).round(2)

          result
        rescue StandardError => e
          execution_time = Time.now - start_time
          record_failed_execution(execution_time, e)

          payload[:success] = false
          payload[:execution_time_ms] = (execution_time * 1000).round(2)
          payload[:error] = e.class.name

          raise
        ensure
          StarGates.telemetry&.record_feature_execution(
            feature_identifier,
            status,
            !defined?(e),
            payload[:execution_time_ms],
            context
          )
        end
      end
    end

    def instrument_ui_access(context)
      return yield unless telemetry_enabled?

      # Use ActiveSupport::Notifications for UI access tracking
      ActiveSupport::Notifications.instrument('star_gates.ui_component.access',
                                              feature: feature_identifier,
                                              context: context) do |payload|
        result = yield
        payload[:component] = result

        StarGates.telemetry&.record_counter(
          'star_gates.ui_component.access',
          1,
          tags: telemetry_tags.merge(component: result, feature: feature_identifier)
        )

        result
      end
    end

    def instrument_config_access(key, context)
      return yield unless telemetry_enabled?

      # Use ActiveSupport::Notifications for config access tracking
      ActiveSupport::Notifications.instrument('star_gates.config.access',
                                              feature: feature_identifier,
                                              config_key: key,
                                              context: context) do |payload|
        result = yield
        payload[:config_value] = result

        StarGates.telemetry&.record_counter(
          'star_gates.config.access',
          1,
          tags: telemetry_tags.merge(config_key: key, feature: feature_identifier)
        )

        result
      end
    end

    def with_timeout(seconds, &)
      if defined?(Timeout)
        Timeout.timeout(seconds, &)
      else
        yield
      end
    rescue Timeout::Error
      raise StarGates::UnavailableError, "Feature #{feature_identifier} timed out after #{seconds}s"
    end

    def record_successful_execution(duration)
      return unless performance_monitoring_enabled?

      @execution_times << duration
      @execution_count += 1
      @last_execution_time = Time.now

      # Keep only last 100 measurements for memory efficiency
      @execution_times = @execution_times.last(100) if @execution_times.size > 100
    end

    def record_failed_execution(duration, _error)
      return unless performance_monitoring_enabled?

      @execution_times << duration
      @execution_count += 1
      @error_count += 1
      @last_execution_time = Time.now
    end

    def calculate_error_rate
      return 0 if @execution_count.nil? || @execution_count.zero?

      (@error_count.to_f / @execution_count * 100).round(2)
    end

    def telemetry_tags
      base_tags = {
        feature: feature_identifier,
        state: status,
        environment: StarGates.configuration.environment
      }

      class_tags = self.class.telemetry_tags || {}
      base_tags.merge(class_tags)
    end

    # State-specific configuration overrides
    def apply_state_specific_config
      case status
      when 'disabled'
        @current_config = @default_config
      when 'canary'
        @current_config = @canary_config.any? ? @canary_config : @feature_config
      when 'enabled'
        @current_config = @feature_config
      end
    end
  end
end

# Add string extensions for better naming
unless String.method_defined?(:demodulize)
  class String
    def demodulize
      split('::').last
    end

    def underscore
      gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
    end
  end
end
