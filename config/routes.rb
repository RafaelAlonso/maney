Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  get "up" => "rails/health#show", as: :rails_health_check

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "home#show"
  get  "setup", to: "setup#new"
  post "setup", to: "setup#create"
  resource :settings, only: %i[edit update]
  resource :analysis, only: :show
  resources :cards, except: :show do
    resource :archival, only: %i[create destroy], controller: "card_archivals"
    resource :migration, only: %i[new create], controller: "card_migrations"
    resources :statements, only: %i[index show]
  end
  resources :categories
  resources :incomes, except: :show
  resources :expenses, except: :show
  resources :budgets, only: :create
end
