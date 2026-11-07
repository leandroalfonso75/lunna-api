class AddShipCostTiersToMlItems < ActiveRecord::Migration[8.1]
  def change
    # Custo do frete grátis do vendedor nas faixas de preço a partir de R$ 79 (frete grátis obrigatório), por faixa:
    # { "79" => custo de R$ 79 a 99,99, "100" => de R$ 100 a 119,99 } — para os cenários de frete da Curva ABC
    add_column :ml_items, :ship_cost_tiers, :jsonb, null: false, default: {}
  end
end
