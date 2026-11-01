# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in star_gates.gemspec

# Use a sibling checkout when there is one, so a change there is tested here
# before it is published, and the published gem otherwise.
%w[deadline_machines probabilistic_machines].each do |name|
  sibling = File.expand_path("../#{name}", __dir__)
  gem name, path: sibling if File.directory?(sibling)
end

gemspec

gem 'benchmark'
gem 'irb'
gem 'rake', '~> 13.0'

gem 'minitest', '~> 6.0'
gem 'minitest-mock', '~> 5.27'
gem 'padded_cell', '~> 0.2'
gem 'railties', '>= 8.1.1'
