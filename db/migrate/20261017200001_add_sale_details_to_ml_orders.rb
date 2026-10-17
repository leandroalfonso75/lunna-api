# Seção Vendas: guarda o pedido completo do Mercado Livre (payload) e o envio (já sem dados
# pessoais do comprador), para a tela mostrar tudo o que a API entrega sem novas consultas.
class AddSaleDetailsToMlOrders < ActiveRecord::Migration[8.1]
  def change
    change_table :ml_orders, bulk: true do |t|
      t.jsonb :payload
      t.bigint :shipping_id
      t.bigint :pack_id
      t.bigint :buyer_id
      t.string :buyer_nickname
      t.decimal :paid_amount, precision: 12, scale: 2
      t.jsonb :shipment
      t.datetime :shipment_synced_at
      t.index :shipping_id
    end

    change_table :ml_order_items, bulk: true do |t|
      t.string :title
      t.string :sku
      t.string :listing_type_id
      t.bigint :variation_id
    end
  end
end
