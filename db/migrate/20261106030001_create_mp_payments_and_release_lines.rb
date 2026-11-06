# Seção Financeiro, aba Repasses (pedido do usuário em 06/11/2026): conciliação geral com o Mercado Pago.
#   - mp_payments: cada pagamento recebido (/v1/payments/search), com as taxas descontadas item a item e o líquido;
#   - mp_release_lines: cada movimento do relatório de liberações da conta (/v1/account/release_report), com o saldo.
class CreateMpPaymentsAndReleaseLines < ActiveRecord::Migration[8.1]
  def change
    create_table :mp_payments do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :payment_id, null: false
      t.bigint :order_id
      t.string :description
      t.string :operation_type
      t.string :status
      t.string :status_detail
      t.datetime :date_created
      t.datetime :date_approved
      t.datetime :date_last_updated
      t.datetime :money_release_date
      t.string :money_release_status
      t.decimal :transaction_amount, precision: 12, scale: 2
      t.decimal :refunded_amount, precision: 12, scale: 2, default: 0
      t.decimal :net_received, precision: 12, scale: 2
      t.decimal :ml_fee, precision: 12, scale: 2, default: 0          # ml_sale_fee
      t.decimal :mp_fee, precision: 12, scale: 2, default: 0          # mp_processing_fee
      t.decimal :financing_fee, precision: 12, scale: 2, default: 0   # mp_financing_* (o financing_fee do parcelamento é do comprador)
      t.decimal :shipping_fee, precision: 12, scale: 2, default: 0    # shp_*
      t.decimal :coupon_amount, precision: 12, scale: 2, default: 0   # coupon_fee: participação do vendedor no cupom
      t.decimal :other_charges, precision: 12, scale: 2, default: 0
      t.jsonb :charges, default: [], null: false
      t.timestamps
    end
    add_index :mp_payments, %i[ml_account_id payment_id], unique: true
    add_index :mp_payments, %i[ml_account_id order_id]
    add_index :mp_payments, %i[ml_account_id date_approved]

    create_table :mp_release_lines do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :file_name, null: false
      t.string :line_key, null: false # hash da linha (o mesmo movimento pode vir em dois relatórios)
      t.datetime :date
      t.bigint :source_id
      t.string :external_reference
      t.string :record_type
      t.string :description
      t.decimal :net_credit, precision: 12, scale: 2, default: 0
      t.decimal :net_debit, precision: 12, scale: 2, default: 0
      t.decimal :gross, precision: 12, scale: 2, default: 0
      t.decimal :mp_fee, precision: 12, scale: 2, default: 0
      t.decimal :financing_fee, precision: 12, scale: 2, default: 0
      t.decimal :shipping_fee, precision: 12, scale: 2, default: 0
      t.decimal :coupon_amount, precision: 12, scale: 2, default: 0
      t.decimal :balance, precision: 14, scale: 2
      t.bigint :order_id
      t.bigint :shipping_id
      t.bigint :pack_id
      t.string :payment_method
      t.timestamps
    end
    add_index :mp_release_lines, %i[ml_account_id line_key], unique: true
    add_index :mp_release_lines, %i[ml_account_id date]
    add_index :mp_release_lines, %i[ml_account_id order_id]

    add_column :ml_accounts, :mp_payments_synced_at, :datetime
    add_column :ml_accounts, :mp_releases_synced_at, :datetime
  end
end
