class CreateMlClaimContests < ActiveRecord::Migration[8.1]
  # Assistente de contestação: o andamento de cada contestação (feita pelo vendedor no ML) e o texto usado.
  def change
    create_table :ml_claim_contests do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :claim_id, null: false
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "pendente" # pendente, contestada, aceita, negada
      t.text :text
      t.datetime :contested_at
      t.timestamps
    end
    add_index :ml_claim_contests, %i[ml_account_id claim_id], unique: true
  end
end
