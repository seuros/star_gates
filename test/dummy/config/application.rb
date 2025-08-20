# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_support/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

# Require the gems listed in Gemfile, including star_gates
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    # Only load the frameworks we need
    config.api_only = true

    # Skip some Rails features we don't need
    config.generators.system_tests = nil

    # Configure StarGates defaults for testing (simplified)
    config.after_initialize do
      Rails.logger.info '[StarGates] StarGates loaded successfully in Rails!'
    end
  end
end
