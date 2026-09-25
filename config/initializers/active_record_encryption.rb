# Configura o ActiveRecord::Encryption a partir de env vars (em vez de Rails
# credentials), para as chaves serem rotacionadas por ambiente sem mexer em
# config/credentials.yml.enc. `access_token`/`refresh_token` de ml_accounts
# usam `encrypts` com estas chaves.
#
# Gerar valores com: bin/rails db:encryption:init
primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

if Rails.env.production? && [ primary_key, deterministic_key, key_derivation_salt ].any?(&:blank?)
  raise <<~MSG
    Faltam as chaves de ActiveRecord::Encryption em produção.
    Defina ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT (veja `bin/rails db:encryption:init`).
  MSG
end

# Em dev/test, chaves fixas e inseguras (placeholder) para `encrypts` funcionar
# sem cada dev ter que rodar db:encryption:init. `local?` (não `!production?`)
# para um ambiente futuro não-local/não-produção não herdar isso por acaso.
if Rails.env.local?
  primary_key ||= "dev-test-insecure-primary-key-do-not-use-in-production"
  deterministic_key ||= "dev-test-insecure-deterministic-key-do-not-use-in-prod"
  key_derivation_salt ||= "dev-test-insecure-key-derivation-salt-do-not-use"
end

Rails.application.config.active_record.encryption.primary_key = primary_key
Rails.application.config.active_record.encryption.deterministic_key = deterministic_key
Rails.application.config.active_record.encryption.key_derivation_salt = key_derivation_salt
