# frozen_string_literal: true

require 'test_helper'
require 'star_gates/adapters/redis_adapter'

class AdaptersTest < Minitest::Test
  # Stand-in for redis-rb: `exists?` answers a boolean, `exists` a count.
  class FakeRedis
    attr_reader :data, :ttls, :published

    def initialize
      @data = {}
      @ttls = {}
      @published = []
    end

    def set(key, value, px: nil)
      data[key] = value
      ttls[key] = px
      'OK'
    end

    def get(key) = data[key]
    def del(key) = data.delete(key) ? 1 : 0
    def exists(key) = data.key?(key) ? 1 : 0
    def exists?(key) = data.key?(key)
    def publish(topic, message) = published << [topic, message]
    def ping = 'PONG'
  end

  def redis_adapter(**config)
    @redis = FakeRedis.new
    StarGates::Adapters::RedisAdapter.new(redis: @redis, **config)
  end

  def test_memory_adapter_storage
    adapter = StarGates::Adapters::MemoryAdapter.new

    adapter.store(:a, 1)
    assert adapter.exists?(:a)
    assert_equal 1, adapter.fetch(:a)
    assert_equal 1, adapter.size
    assert_equal 1, adapter.delete(:a)
    refute adapter.exists?(:a)
    assert adapter.healthy?
  end

  def test_memory_adapter_cache
    adapter = StarGates::Adapters::MemoryAdapter.new

    assert_equal 2, adapter.cache_fetch(:b, expires_in: 1_000) { 2 }
    assert_equal 2, adapter.cache_fetch(:b) { 3 }
    adapter.cache_write(:c, 4, expires_in: 1_000)
    assert_equal 4, adapter.fetch(:c)
    adapter.cache_delete(:c)
    refute adapter.exists?(:c)
  end

  def test_memory_adapter_messaging
    adapter = StarGates::Adapters::MemoryAdapter.new
    received = []

    adapter.subscribe(:topic) { |message| received << message }
    adapter.publish(:topic, 'hello')
    assert_equal ['hello'], received
    assert_equal 1, adapter.topics_count
    assert_equal 1, adapter.subscribers_count(:topic)

    adapter.clear!
    assert_equal 0, adapter.size
    assert_equal 0, adapter.topics_count
  end

  # Bug: redis-rb's `exists?` answers a boolean, and `true.positive?` raised
  # NoMethodError.
  def test_redis_adapter_exists
    adapter = redis_adapter

    refute adapter.exists?('a')
    adapter.store('a', 'x')
    assert adapter.exists?('a')
  end

  def test_redis_adapter_storage_round_trips
    adapter = redis_adapter

    adapter.store('a', { 'n' => 1 })
    assert_equal({ 'n' => 1 }, adapter.fetch('a'))
    adapter.store('s', 'plain')
    assert_equal 'plain', adapter.fetch('s')
    adapter.delete('a')
    assert_nil adapter.fetch('a')
    assert adapter.healthy?
  end

  def test_redis_ttls_are_nanoseconds_rounded_up_to_milliseconds
    adapter = redis_adapter(default_ttl: 2_000_000_000)

    adapter.cache_write('a', 1, expires_in: 1_500_001)
    assert_equal 2, @redis.ttls.fetch('star_gates:a')
    adapter.cache_write('b', 1)
    assert_equal 2_000, @redis.ttls.fetch('star_gates:b')
    assert_equal 5, adapter.cache_fetch('c') { 5 }
    assert_equal 2_000, @redis.ttls.fetch('star_gates:c')
    assert_equal 1, adapter.cache_fetch('a') { 9 }
    adapter.cache_delete('a')
    assert_nil adapter.fetch('a')
  end

  # Bug: Redis hands JSON back with String keys and String states, so the
  # projection read nil for :state and :transition_count and broke on the
  # first transition. It normalises on read: Symbol keys, Symbol states.
  def test_feature_projection_over_redis_reads_like_over_memory
    projection = StarGates::Projections::FeatureProjection.new(redis_adapter)
    events = StarGates::Events
    projection.handle_event(events::FeatureCreated.new(aggregate_id: 'p', data: { rollout_percentage: 5 }))
    projection.handle_event(events::FeatureStateChanged.new(aggregate_id: 'p', from_state: :disabled,
                                                            to_state: :enabled, event_name: :enable))
    projection.handle_event(events::FeatureExecuted.new(aggregate_id: 'p', context: {}, result: true,
                                                        execution_time: 1))

    feature = projection.find_feature('p')
    assert_equal :enabled, feature[:state]
    assert_equal [1, 1, 5], feature.values_at(:transition_count, :execution_count, :rollout_percentage)
    assert_equal ['p'], projection.find_features_by_state(:enabled).map { |f| f[:id] }
    assert_empty projection.find_features_by_state(:disabled)
    assert_equal({ disabled: 0, canary: 0, enabled: 1 }, projection.feature_stats[:by_state])
    assert_equal 1, projection.feature_stats[:total_executions]
    assert_equal 1, projection.feature_stats[:recent_transitions]
    transition = projection.recent_transitions(limit: 1).first
    assert_equal %i[disabled enabled enable], transition.values_at(:from_state, :to_state, :event_name)
  end

  def test_redis_publish_serializes
    adapter = redis_adapter(key_prefix: 'app')

    adapter.publish('flags', { 'on' => true })
    assert_equal [['app:topics:flags', '{"on":true}']], @redis.published
  end

  def test_base_adapter_needs_the_storage_methods
    adapter = StarGates::Adapters::BaseAdapter.new

    %i[fetch delete exists?].each { |name| assert_raises(NotImplementedError) { adapter.public_send(name, :k) } }
    assert_raises(NotImplementedError) { adapter.store(:k, 1) }
    assert_nil adapter.publish(:t, 1)
    assert_nil adapter.subscribe(:t) { nil }
    assert adapter.healthy?
  end

  def test_base_adapter_cache_goes_through_storage
    adapter = Class.new(StarGates::Adapters::BaseAdapter) do
      def initialize = (super; @data = {})
      def store(key, value) = @data[key] = value
      def fetch(key) = @data[key]
      def delete(key) = @data.delete(key)
      def exists?(key) = @data.key?(key)
    end.new

    assert_equal 1, adapter.cache_fetch(:a) { 1 }
    assert_equal 1, adapter.cache_fetch(:a) { 2 }
    adapter.cache_write(:b, 3)
    assert_equal 3, adapter.fetch(:b)
    adapter.cache_delete(:b)
    refute adapter.exists?(:b)
  end
end
