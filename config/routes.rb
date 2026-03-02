Rails.application.routes.draw do
  # Dashboard root (unscoped)
  root to: redirect("/blackboard/dashboard")

  scope "/blackboard" do
    get "/", to: redirect("/blackboard/dashboard")

    # Dashboard
    get "dashboard", to: "dashboard#index"
    get "dashboard/stats", to: "dashboard#stats", as: :dashboard_stats
    post "dashboard/tick", to: "dashboard#tick", as: :tick_dashboard

    # Main resources
    resources :observables, only: [:index, :show]
    resources :hypotheses, only: [:index, :show]
    resources :campaigns, only: [:index]
    resources :alerts, only: [:index, :show] do
      member do
        post :acknowledge
        post :resolve
        post :false_positive
        post :add_historical_knowledge
      end
    end
    resources :critiques, only: [:index] do
      member do
        post :rebut
      end
    end
    resources :verifications, only: [:index]
    resources :knowledge_sources, only: [:index, :show, :edit, :update] do
      member do
        post :invoke
        post :toggle_active
      end
    end
    resources :decisions, only: [:index]

    # Settings
    resources :settings, only: [:index, :update] do
      collection do
        post :reset_defaults
        post :toggle_processing
        post :clear_data
        post :apply_preset
      end
    end

    # Sensor configuration
    resources :sensors, only: [:index, :new, :create, :edit, :update, :destroy] do
      member do
        post :toggle
        post :ingest
      end
      collection do
        post :switch_platform
      end
    end

    # API endpoints
    namespace :api do
      resources :observables, only: [:index, :create] do
        collection do
          post :batch
        end
      end

      resources :hypotheses, only: [:index, :show] do
        member do
          get :chain
        end
      end

      resources :alerts, only: [:index, :show] do
        member do
          patch :acknowledge
          patch :resolve
          patch :false_positive
        end
      end

      get "blackboard/status", to: "blackboard#status"
      post "blackboard/tick", to: "blackboard#tick"
    end

    # Sidekiq admin
    get "sidekiq", to: "sidekiq_admin#index", as: :sidekiq_admin
    get "sidekiq/logs", to: "sidekiq_admin#logs", as: :sidekiq_logs
    post "sidekiq/start_ingestion", to: "sidekiq_admin#start_ingestion", as: :start_ingestion_sidekiq
    post "sidekiq/stop_ingestion",  to: "sidekiq_admin#stop_ingestion",  as: :stop_ingestion_sidekiq
    post "sidekiq/start_supervisor", to: "sidekiq_admin#start_supervisor", as: :start_supervisor_sidekiq
    post "sidekiq/stop_supervisor",  to: "sidekiq_admin#stop_supervisor",  as: :stop_supervisor_sidekiq
    post "sidekiq/clear_retries", to: "sidekiq_admin#clear_retries", as: :clear_retries_sidekiq
    post "sidekiq/clear_dead", to: "sidekiq_admin#clear_dead", as: :clear_dead_sidekiq

    # Health check
    get "up", to: proc { [200, {}, ["OK"]] }
  end
end
