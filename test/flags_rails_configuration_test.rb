# frozen_string_literal: true

require 'test_helper'
require 'rails/application'

class FlagsRailsConfigurationTest < Minitest::Test
  def setup
    super
    @configuration = Rails::Application::Configuration.new(Pathname.new(__dir__))
    @configuration.x.feature_flags = { preview: true }
    @env = {}
    @flags = StarGates::Flags.new(env: @env, configuration: -> { @configuration.x.feature_flags })
  end

  def test_resolves_rails_defaults_lazily_including_replaced_configuration
    assert @flags.enabled?(:preview)
    @configuration.x.feature_flags[:preview] = false
    @flags.enable(:preview)
    refute @flags.enabled?(:preview)

    @configuration.x.feature_flags = { preview: true }
    assert @flags.enabled?(:preview)
    assert_equal 'config:preview', @flags.debug(:preview)[:source]
  end

  def test_environment_can_disable_a_rails_default
    @env['FEATURE_PREVIEW'] = 'false'
    refute @flags.enabled?(:preview)
    assert_equal 'environment:FEATURE_PREVIEW', @flags.debug(:preview)[:source]
    @env.delete('FEATURE_PREVIEW')
    assert @flags.enabled?(:preview)
  end

  def test_runtime_removal_and_reset_do_not_change_rails_defaults
    @flags.enable(:runtime_only, metadata: { reason: 'test' })
    assert @flags.enabled?(:runtime_only)
    @flags.remove(:runtime_only)
    refute @flags.enabled?(:runtime_only)
    assert_empty @flags.flag_status(:runtime_only)[:metadata]

    @flags.enable(:runtime_only, metadata: { reason: 'test' })
    @flags.reset!
    refute @flags.enabled?(:runtime_only)
    assert_empty @flags.flag_status(:runtime_only)[:metadata]
    assert @flags.enabled?(:preview)
    assert_equal({ preview: true }, @configuration.x.feature_flags)
  end

  def test_inventories_arbitrary_rails_defaults
    @configuration.x.feature_flags[:custom_rollout] = true
    @configuration.x.feature_flags[:disabled_rollout] = false

    assert_equal %w[custom_rollout disabled_rollout preview], @flags.all.keys.sort
    assert_equal %i[custom_rollout preview], @flags.enabled_flags.sort
    assert_equal %i[custom_rollout disabled_rollout preview], @flags.summary[:configuration_flags].sort
  end
end
