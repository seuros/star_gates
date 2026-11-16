# frozen_string_literal: true

class CircuitsController < ApplicationController
  def index
    circuits = BreakerMachines.registry.all_circuits.map do |circuit|
      stats = circuit.stats
      policy = circuit.policy

      {
        name: circuit.name,
        state: stats.state,
        failure_count: stats.failure_count,
        success_count: stats.success_count,
        last_failure_at: stats.last_failure_at,
        policy: {
          failure_threshold: policy.threshold.count,
          failure_rate: policy.threshold.rate,
          window: policy.window,
          cooldown: policy.recovery.cooldown
        }
      }
    end

    render json: { circuits: circuits }
  end

  def reset
    circuit = BreakerMachines.registry.all_circuits.find { |c| c.name.to_s == params[:name] }

    if circuit
      circuit.reset
      render json: {
        message: "Circuit #{params[:name]} reset successfully",
        state: circuit.status_name
      }
    else
      render json: { error: 'Circuit not found' }, status: :not_found
    end
  end
end
