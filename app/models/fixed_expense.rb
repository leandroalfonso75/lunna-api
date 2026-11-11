# Despesa fixa mensal da empresa (aluguel, salários, FGTS, INSS...), lançada em Financeiro › Despesas › Incluir Despesas.
# O total do mês sobre o faturamento do mês vira o percentual de despesas fixas das vendas daquele mês (ver
# Painel::FixedExpenseRate).
class FixedExpense < ApplicationRecord
  CATEGORIES = [ "Aluguel", "Salários", "FGTS", "INSS", "Bonificações", "Pró-labore", "Transporte", "Material de expediente",
                 "Energia, água e internet", "Contador", "Software e assinaturas", "Outras" ].freeze

  belongs_to :company
  belongs_to :user, optional: true

  normalizes :month, with: ->(value) { value&.to_date&.beginning_of_month }

  validates :month, :category, presence: true
  validates :amount, numericality: { greater_than: 0 }
end
