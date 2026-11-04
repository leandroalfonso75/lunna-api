# Frete por unidade se o anúncio oferecesse frete grátis (Curva ABC: "Testar frete grátis" mostra custos e margem).
class AddShipCostFreeToMlItems < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_items, :ship_cost_free, :decimal, precision: 12, scale: 2
  end
end
