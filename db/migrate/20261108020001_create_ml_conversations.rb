class CreateMlConversations < ActiveRecord::Migration[8.1]
  def change
    # Seção Mensagens: conversas de pós-venda do Mercado Livre (uma por pack/pedido), com as mensagens em jsonb
    create_table :ml_conversations do |t|
      t.uuid :ml_account_id, null: false
      t.bigint :pack_id, null: false # pack_id do carrinho ou o order_id
      t.bigint :buyer_id
      t.string :status
      t.string :substatus
      t.jsonb :claim_ids, null: false, default: []
      t.jsonb :messages, null: false, default: []
      t.integer :messages_count, null: false, default: 0
      t.integer :unread_count, null: false, default: 0
      t.datetime :last_message_at
      t.string :last_from # buyer | seller
      t.integer :seller_max_length
      t.datetime :checked_at
      t.timestamps
    end
    add_index :ml_conversations, [ :ml_account_id, :pack_id ], unique: true
    add_index :ml_conversations, [ :ml_account_id, :last_message_at ]

    # Mensagens enviadas pelo Lunna (registro de cada envio)
    create_table :ml_message_sends do |t|
      t.uuid :ml_account_id, null: false
      t.bigint :pack_id, null: false
      t.uuid :user_id
      t.text :text, null: false
      t.boolean :ok, null: false, default: false
      t.string :error
      t.timestamps
    end

    # Vendas já conferidas (se têm conversa) e respostas padrão por tipo (pergunta / mensagem)
    add_column :ml_orders, :messages_checked_at, :datetime
    add_column :question_templates, :kind, :string, null: false, default: "pergunta"
    add_index :question_templates, [ :company_id, :kind ]
  end
end
