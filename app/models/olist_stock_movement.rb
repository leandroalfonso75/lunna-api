# Movimentação de estoque do Olist (Suprimentos > Controle de Estoque). Guardada
# para calcular o custo PEPS; substituída por inteiro a cada leitura do produto.
class OlistStockMovement < ApplicationRecord
  KINDS = %w[E S B].freeze

  belongs_to :company

  validates :kind, inclusion: { in: KINDS }
end
