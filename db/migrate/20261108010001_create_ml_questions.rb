class CreateMlQuestions < ActiveRecord::Migration[8.1]
  def change
    # Seção Perguntas: perguntas dos compradores nos anúncios do Mercado Livre
    create_table :ml_questions do |t|
      t.uuid :ml_account_id, null: false
      t.bigint :question_id, null: false
      t.string :item_id
      t.string :status
      t.text :text
      t.datetime :date_created
      t.bigint :from_id
      t.text :answer_text
      t.string :answer_status
      t.datetime :answer_date
      t.boolean :hold, null: false, default: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :ml_questions, [ :ml_account_id, :question_id ], unique: true
    add_index :ml_questions, [ :ml_account_id, :status, :date_created ]

    # Respostas enviadas pelo Lunna (registro de cada envio ao ML)
    create_table :ml_question_answers do |t|
      t.uuid :ml_account_id, null: false
      t.bigint :question_id, null: false
      t.uuid :user_id
      t.text :text, null: false
      t.boolean :ok, null: false, default: false
      t.string :error
      t.timestamps
    end
    add_index :ml_question_answers, [ :ml_account_id, :question_id ]

    # Respostas padrão da empresa (botão "Respostas padrão")
    create_table :question_templates do |t|
      t.uuid :company_id, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :question_templates, [ :company_id, :position ]

    add_column :ml_accounts, :questions_synced_at, :datetime
  end
end
