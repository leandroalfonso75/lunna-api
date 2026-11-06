# Seção Financeiro, abas Receita e Despesas (pedido do usuário em 05/11/2026): lançamentos manuais de outras receitas
# e despesas (o que não vem do Mercado Livre), que entram no DRE do período.
class CreateFinanceEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :finance_entries do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :entry_type, null: false # receita | despesa
      t.date :date, null: false
      t.string :category, null: false
      t.string :description, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.text :notes
      t.timestamps
    end
    add_index :finance_entries, %i[ml_account_id date]
  end
end
