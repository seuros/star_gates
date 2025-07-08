# frozen_string_literal: true

require 'test_helper'

class FlagsTest < Minitest::Test
  def setup
    super
    @env = {}
    @configuration = {}
    @flags = StarGates::Flags.new(env: @env, configuration: -> { @configuration })
  end

  def test_unknown_and_invalid_flags_are_disabled
    [nil, '', 123, [], {}, 'missing', 'bad name'].each do |name|
      refute @flags.enabled?(name)
      assert_equal 'default', @flags.debug(name)[:source]
    end
    assert_raises(ArgumentError) { @flags.enable(nil) }
  end

  def test_precedence_and_explicit_false
    @flags.enable(:copilot)
    @configuration[:copilot] = false
    refute @flags.enabled?(:copilot)
    assert_equal 'config:copilot', @flags.debug(:copilot)[:source]

    @env['FEATURE_COPILOT'] = 'true'
    assert @flags.enabled?(:copilot)
    @env['FEATURE_COPILOT'] = 'false'
    refute @flags.enabled?(:copilot)
    assert_equal 'environment:FEATURE_COPILOT', @flags.debug(:copilot)[:source]

    @env.delete('FEATURE_COPILOT')
    @configuration.clear
    assert @flags.enabled?(:copilot)
    @flags.disable(:copilot)
    refute @flags.enabled?(:copilot)
    assert_equal 'runtime', @flags.debug(:copilot)[:source]
  end

  def test_configuration_is_read_on_every_check
    @configuration[:copilot] = true
    assert @flags.enabled?(:copilot)
    @configuration[:copilot] = false
    refute @flags.enabled?(:copilot)
    @configuration[:copilot] = nil
    assert_equal 'default', @flags.debug(:copilot)[:source]
  end

  def test_accepts_plain_hash_configuration
    flags = StarGates::Flags.new(env: {}, configuration: { copilot: true })
    assert flags.enabled?(:copilot)
    flags.configuration = { copilot: false }
    refute flags.enabled?(:copilot)
  end

  def test_invalid_configuration_is_not_silently_swallowed
    @flags.configuration = -> {}
    assert_raises(ArgumentError) { @flags.enabled?(:copilot) }
  end

  def test_boolean_strings_are_consistent_for_environment_and_runtime
    %w[true TRUE True 1 yes YES Yes on ON On].each do |value|
      @env['FEATURE_TRUTHY'] = value
      @flags.set(:runtime, value)
      assert @flags.enabled?(:truthy), value
      assert @flags.enabled?(:runtime), value
      assert_includes @flags.enabled_flags, :truthy
    end

    %w[false FALSE 0 no NO off OFF unknown].each do |value|
      @env['FEATURE_FALSY'] = value
      @flags.set(:runtime, value)
      refute @flags.enabled?(:falsy), value
      refute @flags.enabled?(:runtime), value
    end
  end

  def test_blank_environment_values_fall_through
    @configuration[:copilot] = true
    ['', '   '].each do |value|
      @env['FEATURE_COPILOT'] = value
      assert @flags.enabled?(:copilot)
      assert_equal 'config:copilot', @flags.debug(:copilot)[:source]
      refute_includes @flags.summary[:environment_flags], :copilot
    end
  end

  def test_names_are_normalized_across_all_sources
    @flags.enable('Test-Flag')
    assert @flags.enabled?(:test_flag)
    @configuration['Test-Flag'] = false
    refute @flags.enabled?('TEST-FLAG')
    @env['FEATURE_TEST_FLAG'] = 'yes'
    assert @flags.enabled?(:test_flag)
    assert_equal ['test_flag'], @flags.all.keys
  end

  def test_inventory_and_summary_include_only_boolean_configuration
    @flags.enable(:runtime)
    @configuration.merge!(configured: true, disabled: false, ignored: nil, other: 'text')
    @env['FEATURE_ENV_FLAG'] = 'on'
    @env['UNRELATED'] = 'true'

    assert_equal %w[configured disabled env_flag runtime], @flags.all.keys.sort
    assert_equal %i[configured env_flag runtime], @flags.enabled_flags.sort
    assert_equal [:runtime], @flags.summary[:runtime_flags]
    assert_equal [:env_flag], @flags.summary[:environment_flags]
    assert_equal %i[configured disabled], @flags.summary[:configuration_flags].sort
  end

  def test_debug_reports_the_effective_source_and_underlying_values
    @flags.enable(:copilot)
    @configuration[:copilot] = false
    @env['FEATURE_COPILOT'] = 'yes'
    details = @flags.debug(:copilot)

    assert_equal :copilot, details[:flag]
    assert_equal true, details[:value]
    assert_equal 'yes', details[:environment_value]
    assert_equal false, details[:configuration_value]
    assert_equal true, details[:runtime_value]
  end

  def test_metadata_is_copied_and_reset_with_runtime_state
    metadata = { reason: 'preview' }
    @flags.enable(:copilot, metadata: metadata)
    metadata[:reason] = 'changed'
    status = @flags.flag_status(:copilot)
    assert_equal({ reason: 'preview' }, status[:metadata])
    status[:metadata][:reason] = 'also changed'
    assert_equal({ reason: 'preview' }, @flags.flag_status(:copilot)[:metadata])
    @flags.reset!
    assert_empty @flags.flag_status(:copilot)[:metadata]
    refute @flags.enabled?(:copilot)
  end

  def test_remove_and_reset_preserve_external_configuration
    @configuration[:configured] = true
    @env['FEATURE_ENV_FLAG'] = 'true'
    @flags.enable(:runtime, metadata: { reason: 'test' })
    @flags.remove(:runtime)
    refute @flags.enabled?(:runtime)
    assert_empty @flags.flag_status(:runtime)[:metadata]
    @flags.enable(:runtime)
    @flags.reset!
    refute @flags.enabled?(:runtime)
    assert @flags.enabled?(:configured)
    assert @flags.enabled?(:env_flag)
  end

  def test_runtime_transitions_are_idempotent
    2.times { @flags.enable(:copilot) }
    assert @flags.enabled?(:copilot)
    2.times { @flags.disable(:copilot) }
    refute @flags.enabled?(:copilot)
  end

  def test_conditional_enable
    @flags.enable_if(:copilot) { true }
    assert @flags.enabled?(:copilot)
    @flags.enable_if(:copilot) { false }
    refute @flags.enabled?(:copilot)
  end

  def test_concurrent_runtime_changes
    threads = 10.times.map do |index|
      Thread.new do
        name = "thread_#{index}"
        10.times do
          @flags.enable(name)
          @flags.disable(name)
        end
        @flags.enable(name)
      end
    end
    threads.each(&:value)
    assert_equal 10, @flags.enabled_flags.size
  end

  def test_global_registry_is_stable
    assert_same StarGates.flags, StarGates.flags
    assert_instance_of StarGates::Flags, StarGates.flags
  end
end
