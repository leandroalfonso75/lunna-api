class CreateMlClaimReplies < ActiveRecord::Migration[8.1]
  # Respostas enviadas pelo Lunna nas reclamações do Mercado Livre (auditoria: quem, quando, para quem, texto, resultado).
  def change
    create_table :ml_claim_replies do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :claim_id, null: false
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :receiver_role, null: false
      t.text :message, null: false
      t.string :status, null: false, default: "pending" # pending, sent, failed
      t.string :error
      t.jsonb :response, default: {}, null: false
      t.timestamps
    end
    add_index :ml_claim_replies, %i[ml_account_id claim_id]
  end
end
