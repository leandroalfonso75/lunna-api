# Contestação com IA a partir do relato completo da reclamação (pedido do usuário em 17/11/2026).
class AddAiToMlClaimContests < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_claim_contests, :ai_text, :text
    add_column :ml_claim_contests, :ai_notes, :jsonb, default: {}, null: false
    add_column :ml_claim_contests, :ai_generated_at, :datetime
    add_column :ml_claim_contests, :ai_error, :string
  end
end
