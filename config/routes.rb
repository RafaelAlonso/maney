Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
  get  "setup", to: "setup#new"
  post "setup", to: "setup#create"
  resource :settings, only: %i[edit update]
  resources :cards, except: :show do
    resource :migration, only: %i[new create], controller: "card_migrations"
  end
  resources :categories
  resources :incomes, except: :show
  resources :expenses, except: :show
end
