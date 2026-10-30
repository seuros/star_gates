# frozen_string_literal: true

require_relative 'lib/star_gates/version'

Gem::Specification.new do |spec|
  spec.name = 'star_gates'
  spec.version = StarGates::VERSION
  spec.authors = ['Abdelkader Boudih']
  spec.email = ['terminale@gmail.com']

  spec.summary = 'A Ruby gem for building DSL-based star gate configurations'
  spec.description = 'StarGates provides a domain-specific language for defining and managing ' \
                     'star gate configurations with circuit breaker patterns.'
  spec.homepage = 'https://github.com/seuros/star_gates'
  spec.license = 'BSD-3-Clause'
  spec.required_ruby_version = '>= 4.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/seuros/star_gates'
  spec.metadata['changelog_uri'] = 'https://github.com/seuros/star_gates/blob/master/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_dependency 'activesupport', '>= 8.1.1'
  spec.add_dependency 'concurrent-ruby', '>= 1.3.5'
  spec.add_dependency 'state_machines', '>= 0.202.0'
  spec.add_dependency 'zeitwerk', '>= 2.7.3'

  # Ecosystem dependencies - distributed systems reliability
  spec.add_dependency 'breaker_machines', '>= 0.22.1' # Circuit breaker pattern
  spec.add_dependency 'chrono_machines', '>= 0.3.0' # Exponential backoff retries

  # Optional dependencies
  # spec.add_dependency 'jsonrpc-rails'  # JSON-RPC API support (optional)

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
