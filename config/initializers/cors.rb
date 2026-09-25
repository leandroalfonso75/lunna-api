# Be sure to restart your server when you modify this file.

# CORS restrito às origens configuradas via CORS_ORIGINS (vírgula-separado).
# Default: servidor de dev do front Nuxt (porta 3101).
cors_origins = ENV.fetch("CORS_ORIGINS", "http://localhost:3101").split(",").map(&:strip)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins cors_origins

    resource "*",
      headers: :any,
      methods: [ :get, :post, :patch, :put, :delete, :options ]
  end
end
