# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in star_gates.gemspec
gemspec

# An untracked Gemfile.local may point sibling gems at local checkouts, to
# test a change there before it is published. It is never committed.
local = File.expand_path('Gemfile.local', __dir__)
eval_gemfile local if File.exist?(local)

gem 'benchmark'
gem 'irb'
gem 'rake', '~> 13.0'

gem 'minitest', '~> 6.0'
gem 'minitest-mock', '~> 5.27'
gem 'padded_cell', '~> 0.2'
gem 'railties', '>= 8.1.1'
gem 'rbs', '~> 3.0'
