class AddReviewToMlAdDecisions < ActiveRecord::Migration[8.1]
  # Ads > Análise > Histórico de Ações (pedido do usuário em 10/11/2026): a ação marcada como "Feito" fica no histórico
  # até a revisão (8º dia), quando mostra a evolução e pede "Aguardar mais 7 dias" ou "Arquivar"; arquivada, some.
  # follow_ups guarda o que foi feito depois (novas sugestões marcadas como feitas, esperas de mais 7 dias).
  def up
    add_column :ml_ad_decisions, :review_at, :datetime
    add_column :ml_ad_decisions, :archived_at, :datetime
    add_column :ml_ad_decisions, :follow_ups, :jsonb, null: false, default: []
    execute "UPDATE ml_ad_decisions SET review_at = decided_at + interval '7 days' WHERE status = 'feito'"
  end

  def down
    remove_column :ml_ad_decisions, :follow_ups
    remove_column :ml_ad_decisions, :archived_at
    remove_column :ml_ad_decisions, :review_at
  end
end
