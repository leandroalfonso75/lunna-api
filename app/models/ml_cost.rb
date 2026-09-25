# Custo por SKU (DECISOES §3/§9). Por empresa, compartilhado entre as contas;
# sem UI/carga na v1.
class MlCost < ApplicationRecord
  belongs_to :company

  validates :sku, presence: true, uniqueness: { scope: :company_id }
end
