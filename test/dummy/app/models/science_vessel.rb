# frozen_string_literal: true

require_relative 'base_ship'

class ScienceVessel < BaseShip
  attr_reader :research_labs, :probe_inventory

  def initialize(name, registry_number)
    super
    @research_labs = %i[xenobiology astrophysics quantum_mechanics]
    @probe_inventory = 20
  end

  def scan_anomaly(anomaly_type)
    activate(:sensor_array) { "Scanning #{anomaly_type} anomaly... Fascinating data collected!" }
  end

  def conduct_experiment(experiment_name, lab = :xenobiology)
    activate(:laboratory) do
      activate(:containment_field) do
        raise 'Invalid laboratory' unless research_labs.include?(lab)

        "Experiment '#{experiment_name}' completed in #{lab} lab"
      end
    end
  end

  def launch_probe(target)
    activate(:probe_launcher) do
      raise 'No probes remaining' if probe_inventory <= 0

      @probe_inventory -= 1
      "Scientific probe launched toward #{target}. #{probe_inventory} probes remaining"
    end
  end

  def analyze_sample(sample_id)
    activate(:laboratory) do
      activate(:sensor_array) { "Sample #{sample_id} analysis complete: Unknown organic compound detected" }
    end
  end

  def establish_containment(hazard_level)
    activate(:containment_field) { "Level #{hazard_level} containment field established" }
  end

  protected

  def configure_gates
    super
    define_system(:sensor_array, threshold: 1, within: 30.seconds, reset_after: 90.seconds,
                  fallback: method(:use_basic_sensors))
    define_system(:laboratory, threshold: 3, within: 3.minutes, reset_after: 2.minutes,
                  fallback: method(:pause_experiments))
    define_system(:probe_launcher, threshold: 5, within: 5.minutes, reset_after: 45.seconds,
                  fallback: method(:prepare_manual_launch))
    define_system(:containment_field, threshold: 1, within: 1.hour, reset_after: 10.minutes,
                  fallback: method(:emergency_containment_protocol))
  end

  def use_basic_sensors
    log_event('Falling back to basic sensor package')
    'Basic sensors only - 20% effectiveness'
  end

  def pause_experiments
    log_event('All experiments paused for safety')
    'Experiments suspended - data preserved'
  end

  def prepare_manual_launch
    log_event('Preparing for manual probe launch')
    'Manual probe launch prepared - 5 minute delay'
  end

  def emergency_containment_protocol
    log_event('EMERGENCY: Ejecting all hazardous samples!')
    'All samples ejected to space - laboratory sealed'
  end
end
