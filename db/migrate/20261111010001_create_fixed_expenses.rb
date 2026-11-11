# Financeiro › Despesas › "Incluir Despesas" (pedido do usuário em 11/11/2026): despesas fixas lançadas por mês (aluguel,
# salários, FGTS, INSS...). O total do mês ÷ faturamento do mês vira o percentual de despesas fixas das vendas daquele
# mês (no lugar do padrão de Configurações › Empresa), depois que o mês fecha. Ver Painel::FixedExpenseRate.
class CreateFixedExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :fixed_expenses do |t|
      t.references :company, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.date :month, null: false # sempre o dia 1º do mês
      t.string :category, null: false
      t.string :description
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.timestamps
    end
    add_index :fixed_expenses, %i[company_id month]
  end
end
