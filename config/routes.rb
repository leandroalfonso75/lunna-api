Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :auth do
    post "sign_up", to: "registrations#create"
    post "sign_in", to: "sessions#create"
    delete "sign_out", to: "sessions#destroy"
    get "ml/callback", to: "ml_callbacks#show"
    get "olist/callback", to: "olist_callbacks#show"
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

    resources :radar_collections, path: "radar/collections", only: [ :index, :create, :destroy ]
    resources :radar_searches, path: "radar/searches", only: [ :index, :show, :create ]

    get "olist", to: "olist#show"
    post "olist/authorize", to: "olist#authorize"
    delete "olist", to: "olist#destroy"
    post "olist/sync", to: "olist#sync"
    get "olist/sync_runs", to: "olist#sync_runs"
    get "olist/products", to: "olist_products#index"
    post "olist/products/remove", to: "olist_products#remove"
    post "olist/products/restore", to: "olist_products#restore"
    get "olist/products/:id", to: "olist_products#show"
    patch "olist/products/:id/price", to: "olist_products#update_price"
    post "olist/products/:id/stock", to: "olist_products#adjust_stock"
    get "olist/changes", to: "olist_products#changes"

    post "sync", to: "sync#create"
    get "sync/runs", to: "sync#runs"

    # Leituras do painel (SPEC 10), sempre com ?account_id= (concern CurrentAccount).
    get "painel", to: "painel#show"
    get "items", to: "items#index"
    get "items/:item_id/title", to: "item_edits#title"
    post "items/:item_id/title/suggest", to: "item_edits#suggest_title"
    post "items/:item_id/title", to: "item_edits#publish_title"
    get "items/:item_id/specs", to: "item_edits#specs"
    post "items/:item_id/specs/suggest", to: "item_edits#suggest_specs"
    post "items/:item_id/specs", to: "item_edits#publish_specs"
    post "items/:item_id/suggestion_acks", to: "item_edits#ack"
    post "items/:item_id/price", to: "item_edits#publish_price"
    get "items/:item_id/photos", to: "photo_jobs#index"
    post "items/:item_id/photos", to: "photo_jobs#create"
    get "photo_images/:id", to: "photo_jobs#image"
    patch "photo_images/:id", to: "photo_jobs#approve"
    post "photo_jobs/:id/publish", to: "photo_jobs#publish"
    post "photo_jobs/:id/check_cover", to: "photo_jobs#check_cover"
    get "items/:id/ai-plan", to: "ai_plans#show"
    post "items/:id/ai-plan", to: "ai_plans#create", as: :item_ai_plan
    delete "items/:id/ai-plan", to: "ai_plans#destroy"
    get "ads", to: "ads#index"
    get "ads/items", to: "ads#items"
    get "ads/analysis", to: "ads#analysis"
    get "ads/diagnosis", to: "ads#diagnosis"
    post "ads/decisions", to: "ads#decide"
    delete "ads/decisions/:id", to: "ads#undecide"
    post "ads/sync", to: "ads#sync"
    get "messages", to: "messages#index"
    post "messages/:pack_id/send", to: "messages#send_message"
    get "questions", to: "questions#index"
    post "questions/:id/answer", to: "questions#answer"
    get "question_templates", to: "questions#templates"
    post "question_templates", to: "questions#create_template"
    patch "question_templates/:id", to: "questions#update_template"
    delete "question_templates/:id", to: "questions#destroy_template"
    get "claims", to: "claims#index"
    get "finance", to: "finance#show"
    get "finance/repasses", to: "finance#repasses"
    get "finance/entries", to: "finance_entries#index"
    post "finance/entries", to: "finance_entries#create"
    patch "finance/entries/:id", to: "finance_entries#update"
    delete "finance/entries/:id", to: "finance_entries#destroy"
    get "claims/returns", to: "claims#returns"
    get "claims/contests", to: "claims#contests"
    patch "claims/:id/contest", to: "claims#contest"
    get "claims/:id", to: "claims#show"
    post "claims/:id/resolve", to: "claims#resolve"
    get "claims/:id/partial_refund_offers", to: "claims#partial_refund_offers"
    get "claims/:id/return_cost", to: "claims#return_cost"
    post "claims/:id/reply", to: "claims#reply"
    get "promotions", to: "promotions#index"
    get "promotions/export", to: "promotions#export"
    post "promotions/sync", to: "promotions#sync"
    get "promotions/items/:item_id", to: "promotions#show", as: :promotion_item
    patch "promotions/items/:item_id/settings", to: "promotions#update_settings"
    patch "promotions/items/:item_id/automation", to: "promotions#update_automation"
    post "promotions/items/:item_id/apply", to: "promotions#apply"
    post "promotions/items/:item_id/leave", to: "promotions#leave"
    post "promotions/apply_best", to: "promotions#apply_best"
    get "promotions/actions", to: "promotions#actions"
    post "promotions/catalog_checks/:id/dismiss", to: "promotions#dismiss_catalog_check"
    get "promotions/runs", to: "promotions#runs"
    post "promotions/runs", to: "promotions#simulate"
    get "promotions/runs/:id", to: "promotions#run"
    get "promotions/runs/:id/export", to: "promotions#run_export"
    get "sales", to: "sales#index"
    post "sales/sync", to: "sales#sync"
    get "sales/:id", to: "sales#show", as: :sale
    get "abc", to: "abc#index"
    get "abc/items/:id", to: "abc#show", as: :abc_item
  end
end
