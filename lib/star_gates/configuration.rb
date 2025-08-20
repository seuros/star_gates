# frozen_string_literal: true

module StarGates
  class Configuration
    attr_accessor :instrumentation, :telemetry_adapter, :default_timeout, :default_retry_count,
                  :circuit_breaker_threshold, :cache_ttl, :environment, :feature_defaults,
                  :enable_performance_monitoring, :log_level, :error_reporting

    def initialize
      @instrumentation = true
      @telemetry_adapter = detect_default_telemetry_adapter
      @default_timeout = 5.0 # seconds
      @default_retry_count = 3
      @circuit_breaker_threshold = 5
      @cache_ttl = 300 # 5 minutes
      @environment = detect_environment
      @feature_defaults = {}
      @enable_performance_monitoring = true
      @log_level = :info
      @error_reporting = true
    end

    # Environment-specific configurations
    def development?
      environment == :development
    end

    def test?
      environment == :test
    end

    def production?
      environment == :production
    end

    def staging?
      environment == :staging
    end

    # Feature-specific defaults
    def feature_config_for(feature_name)
      base_config = {
        timeout: default_timeout,
        retry_count: default_retry_count,
        circuit_breaker_threshold: circuit_breaker_threshold,
        cache_ttl: cache_ttl,
        instrumentation: instrumentation,
        performance_monitoring: enable_performance_monitoring
      }

      # Merge with feature-specific overrides
      feature_specific = feature_defaults[feature_name.to_sym] || {}
      base_config.merge(feature_specific)
    end

    # Configure feature-specific defaults
    def configure_feature(feature_name, config = {})
      feature_defaults[feature_name.to_sym] = config
    end

    # Load from YAML file (Rails-style)
    def load_from_file(file_path)
      return unless File.exist?(file_path)

      require 'yaml'
      config_data = YAML.load_file(file_path)
      env_config = config_data[environment.to_s] || {}

      env_config.each do |key, value|
        setter_method = "#{key}="
        if respond_to?(setter_method)
          send(setter_method, value)
        elsif key == 'features'
          # Handle feature-specific configurations
          value.each { |feature_name, feature_config| configure_feature(feature_name, feature_config) }
        end
      end
    end

    # Environment-aware defaults
    def apply_environment_defaults!
      case environment
      when :development
        @log_level = :debug
        @default_timeout = 10.0 # More generous timeout for dev
        @telemetry_adapter = :memory
      when :test
        @instrumentation = false
        @telemetry_adapter = :memory
        @default_timeout = 1.0  # Fast tests
        @enable_performance_monitoring = false
      when :production
        @log_level = :warn
        @default_timeout = 2.0  # Strict timeout for prod
        @telemetry_adapter = :prometheus
        @error_reporting = true
      when :staging
        @log_level = :info
        @default_timeout = 5.0
        @telemetry_adapter = :prometheus
      end
    end

    # Convert to hash for serialization
    def to_h
      {
        instrumentation: instrumentation,
        telemetry_adapter: telemetry_adapter,
        default_timeout: default_timeout,
        default_retry_count: default_retry_count,
        circuit_breaker_threshold: circuit_breaker_threshold,
        cache_ttl: cache_ttl,
        environment: environment,
        enable_performance_monitoring: enable_performance_monitoring,
        log_level: log_level,
        error_reporting: error_reporting,
        feature_defaults: feature_defaults
      }
    end

    private

    def detect_environment
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.to_sym
      elsif ENV['RACK_ENV']
        ENV['RACK_ENV'].to_sym
      elsif ENV['RAILS_ENV']
        ENV['RAILS_ENV'].to_sym
      elsif ENV['RUBY_ENV']
        ENV['RUBY_ENV'].to_sym
      else
        :development
      end
    end

    def detect_default_telemetry_adapter
      return :prometheus if defined?(Prometheus)
      return :opentelemetry if defined?(OpenTelemetry)

      :memory
    end
  end

  # Global configuration instance
  def self.configuration
    @configuration ||= Configuration.new.tap(&:apply_environment_defaults!)
  end

  def self.configure
    yield(configuration) if block_given?
  end

  # Load configuration from file
  def self.load_config!(file_path = nil)
    file_path ||= default_config_file_path
    configuration.load_from_file(file_path) if file_path
  end

  def self.default_config_file_path
    if defined?(Rails)
      Rails.root.join('config', 'star_gates.yml')
    else
      File.join(Dir.pwd, 'config', 'star_gates.yml')
    end
  end
end
