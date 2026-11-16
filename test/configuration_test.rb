# frozen_string_literal: true

require 'test_helper'
require 'tempfile'
# The default-path test needs Rails loaded with no application; star_gates
# never loads Rails itself.
require 'rails'

class ConfigurationTest < Minitest::Test
  NS_PER_SECOND = 1_000_000_000

  def config(environment = :test)
    StarGates::Configuration.new.tap { |c| c.environment = environment }
  end

  def test_defaults_are_integer_nanoseconds
    c = StarGates::Configuration.new

    assert_equal 5 * NS_PER_SECOND, c.default_timeout
    assert_equal 300 * NS_PER_SECOND, c.cache_ttl
    assert_equal 3, c.default_retry_count
    assert_equal 5, c.circuit_breaker_threshold
    assert c.instrumentation
    assert c.enable_performance_monitoring
    assert c.error_reporting
    assert_equal :info, c.log_level
    assert_equal({}, c.feature_defaults)
    assert_includes %i[memory prometheus opentelemetry], c.telemetry_adapter
  end

  def test_accessors
    c = StarGates::Configuration.new
    c.instrumentation = false
    c.telemetry_adapter = :prometheus
    c.default_timeout = 7
    c.default_retry_count = 1
    c.circuit_breaker_threshold = 9
    c.cache_ttl = 11
    c.feature_defaults = { checkout: { timeout: 1 } }
    c.enable_performance_monitoring = false
    c.log_level = :warn
    c.error_reporting = false

    assert_equal({ instrumentation: false, telemetry_adapter: :prometheus, default_timeout: 7, default_retry_count: 1,
                   circuit_breaker_threshold: 9, cache_ttl: 11, environment: c.environment,
                   enable_performance_monitoring: false, log_level: :warn, error_reporting: false,
                   feature_defaults: { checkout: { timeout: 1 } } }, c.to_h)
  end

  def test_environment_predicates
    assert config(:development).development?
    assert config(:test).test?
    assert config(:production).production?
    assert config(:staging).staging?
    refute config(:test).production?
  end

  def test_environment_defaults_are_nanoseconds
    { development: 10, test: 1, production: 2, staging: 5 }.each do |environment, seconds|
      c = config(environment)
      c.apply_environment_defaults!
      assert_equal seconds * NS_PER_SECOND, c.default_timeout, environment
    end
  end

  def test_feature_config_for_merges_feature_defaults
    c = config
    c.configure_feature('checkout', timeout: 42)

    assert_equal 42, c.feature_config_for(:checkout)[:timeout]
    assert_equal c.default_timeout, c.feature_config_for(:other)[:timeout]
  end

  def test_load_from_file_reads_the_environment_section
    Tempfile.create(['star_gates', '.yml']) do |file|
      file.write(<<~YAML)
        test:
          default_timeout: 250000000
          features:
            checkout:
              timeout: 1
      YAML
      file.flush
      c = config
      c.load_from_file(file.path)

      assert_equal 250_000_000, c.default_timeout
      assert_equal({ timeout: 1 }, c.feature_defaults[:checkout])
    end
  end

  # Bug: YAML overrides kept String keys, so merging them onto the Symbol-keyed
  # defaults added a second 'timeout' entry and the default :timeout won.
  def test_yaml_feature_overrides_win_over_the_defaults
    Tempfile.create(['star_gates', '.yml']) do |file|
      file.write("test:\n  features:\n    checkout:\n      timeout: 1\n      retry_count: 9\n")
      file.flush
      c = config
      c.load_from_file(file.path)

      merged = c.feature_config_for(:checkout)
      assert_equal 1, merged[:timeout]
      assert_equal 9, merged[:retry_count]
      refute merged.key?('timeout'), 'a String key survived the merge'
    end
  end

  def test_load_config_uses_the_given_path
    Tempfile.create(['star_gates', '.yml']) do |file|
      file.write("#{StarGates.configuration.environment}:\n  log_level: :error\n")
      file.flush
      StarGates.load_config!(file.path)

      assert_equal :error, StarGates.configuration.log_level
    end
  end

  # Bug: with Rails loaded but no application (Rails.root nil), the default
  # path raised NoMethodError, so load_config! with no path did too.
  def test_default_config_file_path_without_a_rails_application
    assert_equal File.join(Dir.pwd, 'config', 'star_gates.yml'), StarGates.default_config_file_path.to_s
    assert_nil StarGates.load_config!
  end
end
