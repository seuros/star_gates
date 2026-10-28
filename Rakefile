# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'shellwords'

desc 'Run gem tests with padded_cell'
task :test do
  sh 'padded_cell', 'test/*_test.rb', *Shellwords.split(ENV.fetch('TESTOPTS', ''))
end

namespace :test do
  desc 'Run Rails integration tests with padded_cell'
  task :rails do
    sh 'padded_cell', 'test/dummy/test', *Shellwords.split(ENV.fetch('TESTOPTS', ''))
  end
end

task default: [:test, 'test:rails']
