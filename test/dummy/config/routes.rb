# frozen_string_literal: true

Rails.application.routes.draw do
  # Health check
  get 'health', to: 'health#show'

  # StarGates Feature Flag API endpoints
  resources :features, only: %i[index show] do
    member do
      post :activate
    end
    collection do
      get :recent_transitions
    end
  end

  # ApplicationStarGate enhanced features
  resources :application_star_gates, only: [:index] do
    member do
      get :introspection
      post :execute
      post :transition
    end
  end

  # Demo endpoints for testing StarGates functionality
  namespace :demo do
    post 'payment', to: 'payments#process_payment'
    get 'payment/methods', to: 'payments#methods'
    get 'payment/fees', to: 'payments#calculate_fees'

    post 'notification', to: 'notifications#send_notification'
    get 'notification/channels', to: 'notifications#channels'

    post 'ai/recommendations', to: 'ai#recommendations'
    post 'ai/analyze', to: 'ai#analyze_behavior'
  end

  # Legacy endpoints (keeping for compatibility)
  get 'weather', to: 'weather#show'
  get 'force_failure', to: 'weather#force_failure'
  get 'circuits', to: 'circuits#index'
  post 'circuits/:name/reset', to: 'circuits#reset'
  get 'test/payment', to: 'test#payment'
  get 'test/notification', to: 'test#notification'
  get 'test/status', to: 'test#status'
  post 'test/trip_payment', to: 'test#trip_payment'
  post 'test/reset', to: 'test#reset'
end
