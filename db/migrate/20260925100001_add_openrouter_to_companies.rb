# DECISOES §10 — chave e modelo da OpenRouter (plano de ação com IA), por
# empresa. `openrouter_api_key` é `text` (cifrado por `encrypts`, coluna cresce
# com a criptografia); `ai_model` é o id OpenRouter (`fornecedor/modelo`).
class AddOpenrouterToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :openrouter_api_key, :text
    add_column :companies, :ai_model, :string
  end
end
