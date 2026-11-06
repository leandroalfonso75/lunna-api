# Lançamento manual do Financeiro: outra receita (ex.: rendimento do Mercado Pago, venda fora do ML) ou outra despesa
# (ex.: embalagens, contador, software), com data, categoria, descrição e valor. Entra no DRE do período.
class FinanceEntry < ApplicationRecord
  TYPES = %w[receita despesa].freeze
  INCOME_CATEGORIES = [ "Rendimentos", "Venda fora do Mercado Livre", "Bonificação / crédito", "Outra receita" ].freeze
  EXPENSE_CATEGORIES = [ "Embalagens e insumos", "Pessoal", "Contador e taxas", "Software e assinaturas", "Marketing fora do ML",
                         "Frete e logística própria", "Perda / avaria", "Outra despesa" ].freeze

  belongs_to :ml_account
  belongs_to :user, optional: true

  validates :entry_type, inclusion: { in: TYPES }
  validates :date, :category, :description, presence: true
  validates :amount, numericality: { greater_than: 0 }
end
