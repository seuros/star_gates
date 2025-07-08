# frozen_string_literal: true

require 'test_helper'

class DurationHelpersTest < Minitest::Test
  def test_loading_star_gates_preserves_duration_helpers
    [1.second, 2.minutes, 3.hours].each do |duration|
      assert_instance_of ActiveSupport::Duration, duration
      assert_kind_of Time, duration.ago
      assert_kind_of Time, duration.from_now
    end
    assert_equal ActiveSupport::Duration, Numeric.instance_method(:minutes).bind_call(1).class
  end

  def test_duration_helpers_with_a_configured_time_zone
    Time.use_zone('UTC') do
      assert_kind_of Time, 0.5.seconds.ago
      assert_kind_of Time, 0.5.seconds.from_now
      assert_instance_of ActiveSupport::TimeWithZone, 0.5.seconds.ago
      assert_instance_of ActiveSupport::TimeWithZone, 0.5.seconds.from_now
    end
  end
end
