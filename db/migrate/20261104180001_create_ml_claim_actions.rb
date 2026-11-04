class CreateMlClaimActions < ActiveRecord::Migration[8.1]
  # Ações de resolução feitas pelo Lunna nas reclamações do ML (oferecer devolução, reembolsar, reembolso parcial,
  # pedir mediação): auditoria de quem, quando, o quê e o resultado (pedido do usuário em 04/11/2026).
  def change
    create_table :ml_claim_actions do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :claim_id, null: false
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :action, null: false # allow_return, refund, partial_refund, open_dispute
      t.jsonb :params, default: {}, null: false
      t.string :status, null: false, default: "pending" # pending, done, failed
      t.string :error
      t.jsonb :response, default: {}, null: false
      t.timestamps
    end
    add_index :ml_claim_actions, %i[ml_account_id claim_id]
  end
end
