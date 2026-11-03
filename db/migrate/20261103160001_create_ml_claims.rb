class CreateMlClaims < ActiveRecord::Migration[8.1]
  # Seção Reclamações (pedido do usuário em 03/11/2026): tudo o que o Mercado Livre informa de cada reclamação da conta
  # (cancelamentos, mediações, devoluções), importado de /post-purchase/v1/claims (lista) e dos detalhes de cada uma.
  def change
    create_table :ml_claims do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :claim_id, null: false
      t.bigint :parent_id
      t.string :resource # order, shipment, ...
      t.bigint :resource_id
      t.bigint :order_id # resource_id quando o recurso é o pedido
      t.string :claim_type # mediations, cancel_purchase, return, ...
      t.string :stage # claim, dispute, recontact, none
      t.string :status # opened, closed
      t.string :reason_id
      t.string :reason_name
      t.string :reason_detail
      t.string :reason_flow
      t.boolean :fulfilled
      t.string :quantity_type
      t.integer :claimed_quantity
      t.string :site_id
      t.datetime :date_created
      t.datetime :last_updated
      t.jsonb :players, default: [], null: false
      t.jsonb :resolution
      t.jsonb :related_entities, default: [], null: false
      # detalhe (o que fazer, prazo, quem deve agir)
      t.string :detail_title
      t.text :detail_description
      t.string :detail_problem
      t.string :action_responsible
      t.datetime :due_date
      # reputação
      t.boolean :affects_reputation
      t.boolean :has_incentive
      # tudo o que a API devolve, sem cortar
      t.jsonb :raw, default: {}, null: false
      t.jsonb :detail, default: {}, null: false
      t.jsonb :messages, default: [], null: false
      t.jsonb :status_history, default: [], null: false
      t.jsonb :actions_history, default: [], null: false
      t.jsonb :expected_resolutions, default: [], null: false
      t.jsonb :evidences, default: [], null: false
      t.jsonb :changes_log, default: [], null: false
      t.jsonb :reputation, default: {}, null: false
      t.jsonb :devolution
      t.jsonb :reason, default: {}, null: false
      t.jsonb :detail_errors, default: {}, null: false # parte que o ML recusou na última leitura
      t.datetime :listed_at
      t.datetime :details_synced_at
      t.timestamps
    end
    add_index :ml_claims, %i[ml_account_id claim_id], unique: true
    add_index :ml_claims, %i[ml_account_id date_created]
    add_index :ml_claims, %i[ml_account_id status]
    add_index :ml_claims, :order_id

    add_column :ml_accounts, :claims_listed_at, :datetime
    add_column :ml_accounts, :claims_full_listed_at, :datetime
  end
end
