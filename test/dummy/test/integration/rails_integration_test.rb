# frozen_string_literal: true

require_relative '../test_helper'

# The host application loads Rails before star_gates (Bundler.require after
# `require 'rails'`), and star_gates picks Rails up from there.
class RailsIntegrationTest < ActiveSupport::TestCase
  test 'configuration follows the host Rails application' do
    configuration = StarGates::Configuration.new

    assert_equal Rails.env.to_sym, configuration.environment
    assert_equal Rails.root.join('config', 'star_gates.yml'), StarGates.default_config_file_path
  end
end
