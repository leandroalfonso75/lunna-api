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
  end
end
