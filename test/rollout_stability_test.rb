# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'

class TestRolloutStability < Minitest::Test
  # CRC32(key.to_s), modulo 100.
  KEY_BUCKETS = {
    1 => 83,
    '1' => 83,
    'resident-123' => 23,
    'account-42' => 52,
    "resident-\u03B1" => 47
  }.freeze

  def test_percentage_rollout_uses_known_stable_buckets
    feature = StarGates::Feature.new(rollout: 50)
    feature.rollout_canary

    KEY_BUCKETS.each do |key, bucket|
      assert_equal bucket, feature.eligibility_debug(key: key)[:hash_modulo], "Bucket for #{key.inspect}"
      assert_equal bucket < 50, feature.enabled_for?(key: key), "Eligibility for #{key.inspect}"
    end
  end

  def test_percentage_rollout_is_stable_in_fresh_ruby_processes
    script = <<~RUBY
      feature = StarGates::Feature.new(rollout: 50)
      feature.rollout_canary
      results = JSON.parse(ARGV.fetch(0)).map do |key|
        [feature.eligibility_debug(key: key)[:hash_modulo], feature.enabled_for?(key: key)]
      end
      puts JSON.generate(results)
    RUBY
    expected = KEY_BUCKETS.values.map { |bucket| [bucket, bucket < 50] }
    library = File.expand_path('../lib', __dir__)

    # Exec fresh interpreters: forked workers can inherit Ruby's hash seed.
    2.times do
      output, errors, status = Open3.capture3(
        Gem.ruby, '-I', library, '-rstar_gates', '-rjson', '-e', script, JSON.generate(KEY_BUCKETS.keys)
      )

      assert status.success?, "#{output}\n#{errors}"
      assert_equal expected, JSON.parse(output)
    end
  end

  def test_percentage_rollout_respects_bucket_boundaries
    { 0 => false, 23 => false, 24 => true, 100 => true }.each do |percentage, expected|
      feature = StarGates::Feature.new(rollout: percentage)
      feature.rollout_canary

      assert_equal expected, feature.enabled_for?(key: 'resident-123'), "Eligibility at #{percentage}%"
    end
  end
end
