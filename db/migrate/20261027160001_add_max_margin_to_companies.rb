# Margem máxima geral das promoções (opcional): acima dela a seção Promoções aplica um desconto maior.
class AddMaxMarginToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :max_margin_pct, :decimal, precision: 6, scale: 2
  end
end
