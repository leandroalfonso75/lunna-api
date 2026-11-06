# Card Devoluções em Reclamações (pedido do usuário em 05/11/2026): custos reais de cada devolução.
#   - ml_claims.return_cost: o que o ML cobra do vendedor pelo frete da devolução, por reclamação
#     (GET /post-purchase/v1/claims/{id}/charges/return-cost; 0 = grátis para o vendedor);
#   - ml_billing_charges: linhas do extrato de faturamento da conta (GET /billing/integration/periods/key/{KEY}/group/ML/details),
#     ligadas à venda e ao envio, para achar frete de envio retido, frete de devolução e outras cobranças/bonificações.
class AddReturnCostAndBillingCharges < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_claims, :return_cost, :decimal, precision: 12, scale: 2
    add_column :ml_claims, :return_cost_at, :datetime

    create_table :ml_billing_charges do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :detail_id, null: false
      t.string :period_key, null: false
      t.string :detail_type   # CHARGE | BONUS ...
      t.string :detail_sub_type
      t.string :transaction_detail
      t.decimal :amount, precision: 12, scale: 2
      t.string :currency_id
      t.bigint :order_id
      t.bigint :shipment_id
      t.string :item_id
      t.datetime :charged_at
      t.jsonb :raw, default: {}, null: false
      t.timestamps
    end
    add_index :ml_billing_charges, %i[ml_account_id detail_id], unique: true
    add_index :ml_billing_charges, %i[ml_account_id order_id]
    add_index :ml_billing_charges, %i[ml_account_id shipment_id]
    add_column :ml_accounts, :billing_synced_at, :datetime
  end
end
