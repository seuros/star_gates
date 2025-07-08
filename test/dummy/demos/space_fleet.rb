# frozen_string_literal: true

require_relative '../app/models/spaceship'
require_relative '../app/models/battle_ship'
require_relative '../app/models/cargo_ship'
require_relative '../app/models/corellian_freighter'
require_relative '../app/models/explorer_ship'
require_relative '../app/models/fighter'
require_relative '../app/models/rmns_atlas_monkey'

module StarGates
  module Examples
    class SpaceFleetDemo
      CrewMember = Data.define(:id, :groups)

      def self.run(output: $stdout)
        ship = Spaceship.new('SG Atlas')
        pilot = CrewMember.new(id: 1, groups: [:pilots])
        passenger = CrewMember.new(id: 2, groups: [:passengers])
        warp = ship.gate(:warp_drive)

        output.puts 'StarGates Space Fleet'
        output.puts "Gate: #{warp.class}; protection: #{warp.circuit.class}"
        output.puts "Underlying breaker: #{warp.circuit.breaker.class}"

        warp.feature.disable
        output.puts "Disabled: #{ship.engage_warp('Alpha Centauri', pilot: pilot)}"

        warp.feature.rollout_canary
        output.puts "Pilot canary: #{ship.engage_warp('Alpha Centauri', pilot: pilot)}"
        output.puts "Passenger fallback: #{ship.engage_warp('Alpha Centauri', pilot: passenger)}"

        warp.feature.enable
        output.puts "Full rollout: #{ship.engage_warp('Alpha Centauri', pilot: passenger)}"

        # Failures exercise the real circuit, not a manual feature transition.
        warp.circuit.threshold.times { ship.engage_warp(:unstable_sector, pilot: pilot) }
        output.puts "Automatic rollback: #{warp.feature.status}; circuit open: #{warp.open?}"
        output.puts "Safe propulsion: #{ship.engage_warp('Alpha Centauri', pilot: pilot)}"

        # Repair and operator approval are explicit. Resetting a circuit does not
        # silently restore a feature to full rollout.
        warp.circuit.reset!
        output.puts "Repaired, pilot canary: #{ship.engage_warp('Alpha Centauri', pilot: pilot)}"
        warp.feature.enable
        output.puts "Operator-approved rollout: #{ship.engage_warp('Alpha Centauri', pilot: passenger)}"
        transitions = warp.feature.transition_history[:transitions].map { |entry| entry[:to_state] }
        output.puts "Feature transitions: #{transitions}"

        freighter = CorellianFreighter.new('Millennium Falcon', 'YT-1300')
        output.puts "Freighter: #{freighter.start_engine}; #{freighter.load_cargo}"
        output.puts "Atlas Monkey: #{atlas_monkey.provide_commentary('success')}"
      end
    end
  end
end

StarGates::Examples::SpaceFleetDemo.run if __FILE__ == $PROGRAM_NAME
