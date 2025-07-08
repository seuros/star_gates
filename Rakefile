# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'minitest/test_task'

Minitest::TestTask.create do |test|
  test.test_globs = ['test/*_test.rb']
end

Minitest::TestTask.create('test:rails') do |test|
  test.libs = %w[lib test/dummy/test .]
  test.test_globs = ['test/dummy/test/**/*_test.rb']
  test.test_prelude = 'require_relative "test/dummy/test/test_helper"'
end

task default: [:test, 'test:rails']
