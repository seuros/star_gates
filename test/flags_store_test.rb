# frozen_string_literal: true

require 'test_helper'
require 'active_support/cache'

class FlagsStoreTest < Minitest::Test
  class StoreWithoutMulti
    def initialize
      @data = {}
    end

    def read(key) = @data[key]
    def write(key, value) = (@data[key] = value) || true
    def delete(key) = @data.delete(key)
    def keys = @data.keys
  end

  class SlowWriteStore < ActiveSupport::Cache::MemoryStore
    def write(...)
      sleep 0.001
      super
    end
  end

  class FailingStore < ActiveSupport::Cache::MemoryStore
    def write(*) = false
  end

  def setup
    super
    @store = ActiveSupport::Cache::MemoryStore.new
    @env = {}
    @configuration = {}
    @flags = build_flags
    @other = build_flags
  end

  def test_changes_are_visible_to_every_instance_sharing_the_store
    @flags.enable(:copilot)
    assert @other.enabled?(:copilot)
    assert_equal 'runtime', @other.debug(:copilot)[:source]

    @other.disable(:copilot)
    refute @flags.enabled?(:copilot)
    assert_equal false, @flags.debug(:copilot)[:runtime_value]
  end

  def test_environment_and_configuration_override_the_store
    @flags.enable(:copilot)
    @configuration[:copilot] = false
    refute @other.enabled?(:copilot)
    assert_equal 'config:copilot', @other.debug(:copilot)[:source]

    @env['FEATURE_COPILOT'] = 'on'
    assert @other.enabled?(:copilot)
    assert_equal 'environment:FEATURE_COPILOT', @other.debug(:copilot)[:source]
  end

  def test_metadata_round_trips_and_survives_disable
    metadata = { reason: 'preview' }
    @flags.enable(:copilot, metadata: metadata)
    metadata[:reason] = 'changed'
    @other.disable(:copilot)

    status = @other.flag_status(:copilot)
    assert_equal({ reason: 'preview' }, status[:metadata])
    assert_equal false, status[:enabled]
    status[:metadata][:reason] = 'mutated'
    assert_equal({ reason: 'preview' }, @flags.flag_status(:copilot)[:metadata])
  end

  def test_inventory_lists_store_flags
    @flags.enable(:runtime)
    @flags.disable(:dark)
    @configuration[:configured] = true

    assert_equal %w[configured dark runtime], @other.all.keys.sort
    assert_equal %i[configured runtime], @other.enabled_flags.sort
    assert_equal %i[runtime dark], @other.summary[:runtime_flags]
  end

  def test_remove_and_reset_clear_the_store
    @flags.enable(:runtime, metadata: { reason: 'test' })
    @flags.enable(:other_flag)
    @other.remove(:runtime)

    refute @flags.enabled?(:runtime)
    assert_empty @flags.flag_status(:runtime)[:metadata]
    assert_equal [:other_flag], @flags.summary[:runtime_flags]

    @other.reset!
    refute @flags.enabled?(:other_flag)
    assert_empty @flags.summary[:runtime_flags]
    assert_empty @store.instance_variable_get(:@data).keys.grep(/\Astar_gates:flags:/)
  end

  def test_concurrent_new_flags_all_stay_listed
    store = SlowWriteStore.new
    threads = Array.new(8) do |i|
      Thread.new { StarGates::Flags.new(env: {}, configuration: {}, store: store).enable("flag_#{i}") }
    end
    threads.each(&:join)

    listed = StarGates::Flags.new(env: {}, configuration: {}, store: store).summary[:runtime_flags]
    assert_equal Array.new(8) { |i| :"flag_#{i}" }.sort, listed.sort
  end

  def test_a_removed_flag_is_listed_once_after_it_returns
    @flags.enable(:runtime)
    @flags.remove(:runtime)
    @other.enable(:runtime)

    assert_equal [:runtime], @flags.summary[:runtime_flags]
  end

  def test_stale_index_entries_are_not_listed
    @flags.enable(:runtime)
    @store.delete('star_gates:flags:flag:runtime')

    assert_empty @other.summary[:runtime_flags]
    assert_equal 'default', @other.debug(:runtime)[:source]
  end

  def test_prefix_isolates_namespaces
    staging = StarGates::Flags.new(env: @env, configuration: -> { @configuration }, store: @store,
                                   prefix: 'staging:flags')
    @flags.enable(:copilot)

    refute staging.enabled?(:copilot)
    staging.reset!
    assert @flags.enabled?(:copilot)
  end

  def test_store_without_values_falls_back_to_default
    flags = StarGates::Flags.new(env: {}, configuration: {}, store: ActiveSupport::Cache::NullStore.new)
    flags.enable(:copilot, metadata: { reason: 'lost' })

    refute flags.enabled?(:copilot)
    assert_equal 'default', flags.debug(:copilot)[:source]
    assert_empty flags.flag_status(:copilot)[:metadata]
    assert_empty flags.summary[:runtime_flags]
  end

  def test_failed_writes_raise
    flags = StarGates::Flags.new(env: {}, configuration: {}, store: FailingStore.new)

    error = assert_raises(StarGates::Error) { flags.enable(:copilot) }
    assert_match(/did not persist/, error.message)
  end

  def test_stores_without_multi_key_operations
    store = StoreWithoutMulti.new
    flags = StarGates::Flags.new(env: {}, configuration: {}, store: store)
    flags.enable(:copilot)
    flags.disable(:preview)

    assert_equal %w[copilot preview], flags.all.keys
    flags.reset!
    assert_empty store.keys
  end

  def test_switching_the_store_drops_process_local_state
    flags = StarGates::Flags.new(env: {}, configuration: {})
    flags.enable(:local_only)
    flags.store = @store

    refute flags.enabled?(:local_only)
    flags.store = nil
    refute flags.enabled?(:local_only)
    assert_nil flags.store
  end

  private

  def build_flags
    StarGates::Flags.new(env: @env, configuration: -> { @configuration }, store: @store)
  end
end
