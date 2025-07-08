# frozen_string_literal: true

require_relative 'base_ship'

class CargoShip < BaseShip
  attr_reader :cargo_capacity, :current_cargo

  def initialize(name, registry_number, capacity = 50_000)
    super(name, registry_number)
    @cargo_capacity = capacity
    @current_cargo = []
  end

  def load_cargo(manifest)
    activate(:cargo_bay) do
      activate(:docking_clamps) do
        if current_cargo.sum { |cargo| cargo[:weight] } + manifest[:weight] > cargo_capacity
          raise 'Cargo capacity exceeded'
        end

        current_cargo << manifest
        "Cargo loaded: #{manifest[:description]} (#{manifest[:weight]} tons)"
      end
    end
  end

  def unload_cargo(cargo_id)
    activate(:cargo_bay) do
      cargo = current_cargo.find { |item| item[:id] == cargo_id }
      raise 'Cargo not found' unless cargo

      current_cargo.delete(cargo)
      "Cargo unloaded: #{cargo[:description]}"
    end
  end

  def refrigerate_cargo
    activate(:refrigeration) do
      "Refrigerating #{current_cargo.count { |cargo| cargo[:perishable] }} perishable items at -20°C"
    end
  end

  def dock_at_station(station_name)
    activate(:docking_clamps) { "Successfully docked at #{station_name}" }
  end

  def cargo_manifest
    activate(:cargo_bay) do
      {
        total_weight: current_cargo.sum { |cargo| cargo[:weight] },
        item_count: current_cargo.count,
        capacity_used: (current_cargo.sum { |cargo| cargo[:weight] }.to_f / cargo_capacity * 100).round(2)
      }
    end
  end

  protected

  def configure_gates
    super
    define_system(:cargo_bay, threshold: 10, within: 5.minutes, reset_after: 2.minutes,
                  fallback: method(:use_manual_cargo_handling))
    define_system(:refrigeration, threshold: 1, within: 10.minutes, reset_after: 5.minutes,
                  fallback: method(:activate_backup_cooling))
    define_system(:docking_clamps, threshold: 5, within: 2.minutes, reset_after: 1.minute,
                  fallback: method(:use_magnetic_locks))
    define_system(:life_support, threshold: 5, within: 2.minutes, reset_after: 1.minute,
                  fallback: method(:activate_zone_isolation))
  end

  def use_manual_cargo_handling
    log_event('Switching to manual cargo operations')
    'Manual cargo handling - operations slowed by 75%'
  end

  def activate_backup_cooling
    log_event('Backup cooling systems engaged')
    'Emergency cooling at 60% efficiency'
  end

  def use_magnetic_locks
    log_event('Magnetic docking locks engaged')
    'Magnetic locks active - limited mobility'
  end

  def activate_zone_isolation
    log_event('Isolating cargo bays from life support')
    'Crew areas sealed - cargo bays on minimal life support'
  end
end
