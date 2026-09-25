Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :auth do
    post "sign_up", to: "registrations#create"
    post "sign_in", to: "sessions#create"
    delete "sign_out", to: "sessions#destroy"
  end

  scope :api do
    get "me", to: "me#show"
    resource :company, only: [ :show, :update ], controller: "company"
    resources :users, only: [ :index, :create, :update, :destroy ]
  end
end
