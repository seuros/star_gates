# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'open3'
require_relative 'dummy/demos/space_fleet'

class SpaceFleetTest < Minitest::Test
  def setup
    super
    @ship = Spaceship.new('SG Atlas', 'SG-1')
    @pilot = MockUser.new(id: 1, groups: [:pilots])
    @passenger = MockUser.new(id: 2, groups: [:passengers])
  end

  def test_systems_are_registered_star_gates_with_linked_features_and_circuits
    @ship.gates.each_value do |gate|
      assert_instance_of StarGates::Gate, gate
      assert_same gate, StarGates[gate.name]
      assert_instance_of StarGates::Feature, gate.feature
      assert_instance_of StarGates::Circuit, gate.circuit
      assert_instance_of BreakerMachines::Circuit, gate.circuit.breaker
      assert_same gate.feature, gate.circuit.feature
      assert gate.feature.enabled?
    end
  end

  def test_disabled_system_uses_fallback_without_touching_hardware
    @ship.gate(:warp_drive).feature.disable
    calls = []

    SpaceflightSystems::WarpDrive.stub(:engage, ->(destination) { calls << destination }) do
      assert_equal 'emergency_mode', @ship.engage_warp('Alpha Centauri', pilot: @pilot)[:status]
    end

    assert_empty calls
    assert_includes @ship.captain_log.last, 'emergency thrusters'
  end

  def test_canary_allows_pilots_and_keeps_passengers_on_safe_propulsion
    @ship.gate(:warp_drive).feature.rollout_canary

    assert_equal 'engaged', @ship.engage_warp('Alpha Centauri', pilot: @pilot)[:status]
    assert_equal 'emergency_mode', @ship.engage_warp('Alpha Centauri', pilot: @passenger)[:status]
    assert_equal 'emergency_mode', @ship.engage_warp('Alpha Centauri')[:status]
  end

  def test_full_rollout_allows_passengers
    assert_equal 'engaged', @ship.engage_warp('Alpha Centauri', pilot: @passenger)[:status]
  end

  def test_failures_open_the_circuit_and_automatically_roll_back_the_feature
    warp = @ship.gate(:warp_drive)
    events = []
    subscriber = ->(_name, _start, _finish, _id, payload) { events << payload }

    ActiveSupport::Notifications.subscribed(subscriber, 'star_gates.circuit.auto_rollback') do
      warp.circuit.threshold.times do
        assert_equal 'emergency_mode', @ship.engage_warp(:unstable_sector, pilot: @pilot)[:status]
      end
    end

    assert warp.open?
    assert_equal 'canary', warp.feature.status
    assert_equal 1, events.size
    assert_equal 'enabled', events.first[:feature_status]
    assert_equal 'emergency_mode', @ship.engage_warp('Alpha Centauri', pilot: @pilot)[:status]
  end

  def test_repair_keeps_canary_targeting_until_an_operator_enables_full_rollout
    warp = @ship.gate(:warp_drive)
    warp.circuit.threshold.times { @ship.engage_warp(:unstable_sector, pilot: @pilot) }

    warp.circuit.reset!

    assert_equal 'canary', warp.feature.status
    assert_equal 'engaged', @ship.engage_warp('Alpha Centauri', pilot: @pilot)[:status]
    assert_equal 'emergency_mode', @ship.engage_warp('Alpha Centauri', pilot: @passenger)[:status]

    warp.feature.enable
    assert_equal 'engaged', @ship.engage_warp('Alpha Centauri', pilot: @passenger)[:status]
  end

  def test_further_failures_disable_an_already_canary_system
    warp = @ship.gate(:warp_drive)
    warp.feature.rollout_canary
    warp.circuit.threshold.times { @ship.engage_warp(:unstable_sector, pilot: @pilot) }

    assert warp.open?
    assert_equal 'disabled', warp.feature.status
    assert_equal :disabled, warp.feature.transition_history[:transitions].first[:to_state]
  end

  def test_ships_with_the_same_registry_number_have_independent_state
    other = Spaceship.new('SG Atlas replica', 'SG-1')
    warp = @ship.gate(:warp_drive)
    other_warp = other.gate(:warp_drive)
    warp.circuit.threshold.times { @ship.engage_warp(:unstable_sector, pilot: @pilot) }

    refute_equal warp.name, other_warp.name
    refute_same warp.feature, other_warp.feature
    refute_same warp.circuit, other_warp.circuit
    assert other_warp.closed?
    assert_equal 'enabled', other_warp.feature.status
    assert_equal 'engaged', other.engage_warp('Alpha Centauri', pilot: @passenger)[:status]
  end

  def test_reactor_retries_a_transient_failure_through_chrono_machines
    attempts = 0
    ignite = lambda do |level|
      attempts += 1
      raise SpaceflightSystems::ReactorOverloadError, 'Transient surge' if attempts == 1

      { status: 'online', power_output: level }
    end

    SpaceflightSystems::FusionReactor.stub(:ignite, ignite) do
      assert_equal({ status: 'online', power_output: 80 }, @ship.power_up_reactor(80))
    end

    assert_equal 2, attempts
    assert @ship.gate(:fusion_reactor).closed?
    assert_equal 'enabled', @ship.gate(:fusion_reactor).feature.status
  end

  def test_navigation_failure_uses_the_ship_fallback
    assert_equal 'manual', @ship.calculate_route(:offline)[:route]
    assert_equal 'calculated', @ship.calculate_route([1, 2, 3])[:route]
  end

  def test_inherited_gates_and_subclass_overrides_are_independent
    fighter = Fighter.new
    freighter = CorellianFreighter.new
    battle_ship = BattleShip.new('Prometheus', 'BC-303')
    cargo_ship = CargoShip.new('Cargo One', 'CS-1')

    assert_equal 3, fighter.gate(:engine).circuit.threshold
    assert_equal 5, freighter.gate(:engine).circuit.threshold
    assert_equal 5, @ship.gate(:navigation).circuit.threshold
    assert_equal 10, battle_ship.gate(:navigation).circuit.threshold
    assert_equal 2, @ship.gate(:life_support).circuit.threshold
    assert_equal 5, cargo_ship.gate(:life_support).circuit.threshold

    freighter.gate(:engine).feature.disable
    assert_equal 'Auxiliary thrusters', freighter.start_engine
    assert_equal 'Engine started', fighter.start_engine
    assert_equal 'Lasers fired', fighter.fire_lasers
    assert_equal 'Cargo loaded', freighter.load_cargo
  end

  def test_science_and_exploration_systems_use_star_gates
    science = ScienceVessel.new('Odyssey', 'SC-1')
    explorer = ExplorerShip.new

    assert_includes science.scan_anomaly('subspace'), 'Fascinating data'
    assert_includes science.launch_probe('Pegasus'), '19 probes remaining'
    assert_equal 'Planet scanned', explorer.scan_planet
    assert_equal 'Probe launched', explorer.launch_probe

    science.gate(:sensor_array).feature.disable
    explorer.gate(:scanner).feature.disable
    assert_equal 'Basic sensors only - 20% effectiveness', science.scan_anomaly('subspace')
    assert_equal 'Using archived planetary charts', explorer.scan_planet
  end

  def test_cargo_operations_keep_their_behavior_behind_gates
    cargo = CargoShip.new('Cargo One', 'CS-1', 100)
    manifest = { id: 1, description: 'Naquadah', weight: 20, perishable: false }

    assert_includes cargo.load_cargo(manifest), 'Naquadah'
    assert_equal({ total_weight: 20, item_count: 1, capacity_used: 20.0 }, cargo.cargo_manifest)
    assert_includes cargo.unload_cargo(1), 'Naquadah'
    assert_empty cargo.current_cargo
  end

  def test_fleet_demo_runs_without_rails_or_optional_gems
    script = File.expand_path('dummy/demos/space_fleet.rb', __dir__)
    output, errors, status = Open3.capture3(Gem.ruby, script)

    assert status.success?, "#{output}\n#{errors}"
    assert_includes output, 'Gate: StarGates::Gate'
    assert_includes output, 'Passenger fallback:'
    assert_includes output, 'Automatic rollback: canary; circuit open: true'
    assert_includes output, 'Operator-approved rollout:'
    assert_includes output, 'Atlas Monkey:'
  end

  def test_dummy_app_eager_loads_the_fleet
    environment = File.expand_path('dummy/config/environment', __dir__)
    script = <<~RUBY
      require #{environment.inspect}
      Rails.application.eager_load!
      ship = Spaceship.new('SG Atlas', 'SG-1')
      abort 'Not a StarGates gate' unless ship.gate(:warp_drive).is_a?(StarGates::Gate)
      abort 'Atlas Monkey unavailable' unless RMNSAtlasMonkey.instance.gate(:sensor_array).is_a?(StarGates::Gate)
      puts ship.engage_warp('Alpha Centauri')[:status]
    RUBY
    output, errors, status = Open3.capture3({ 'RAILS_ENV' => 'test' }, Gem.ruby, '-e', script)

    assert status.success?, "#{output}\n#{errors}"
    assert_includes output, 'engaged'
  end
end
