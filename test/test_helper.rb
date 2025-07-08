# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'star_gates'

require 'minitest/autorun'

class Minitest::Test
  def setup
    StarGates.reset!
  end

  def teardown
    StarGates.reset!
  end
end

class MockUser
  attr_reader :id, :groups

  def initialize(id, groups = [])
    @id = id
    @groups = groups
  end
end
