Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :auth do
    post "sign_up", to: "registrations#create"
    post "sign_in", to: "sessions#create"
    delete "sign_out", to: "sessions#destroy"
    get "ml/callback", to: "ml_callbacks#show"
  end

  namespace :webhooks do
    post "ml", to: "ml#create"
  end

  scope :api do
    get "me", to: "me#show"
    resource :company, only: [ :show, :update ], controller: "company"
    resources :users, only: [ :index, :create, :update, :destroy ]

    resources :ml_accounts, only: [ :index, :destroy ] do
      post :authorize, on: :collection
      post :connect, on: :collection
    end

    post "sync", to: "sync#create"
    get "sync/runs", to: "sync#runs"

    # Leituras do painel (SPEC 10), sempre com ?account_id= (concern CurrentAccount).
    get "painel", to: "painel#show"
    get "items", to: "items#index"
    get "items/:id/ai-plan", to: "ai_plans#show"
    post "items/:id/ai-plan", to: "ai_plans#create", as: :item_ai_plan
    delete "items/:id/ai-plan", to: "ai_plans#destroy"
    get "abc", to: "abc#index"
    get "abc/items/:id", to: "abc#show", as: :abc_item
  end
end
