class CreateMlAdDecisions < ActiveRecord::Migration[8.1]
  def change
    # Histórico das decisões da aba Análise de Ads: o operador marca cada item da fila como feito ou ignorado; o
    # "antes" fica gravado e o "depois" é lido da análise 7 dias depois.
    create_table :ml_ad_decisions do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: true
      t.string :key, null: false       # família (family_id ou item:MLB…) ou "campaign:<id>"
      t.string :signal, null: false
      t.string :klass, null: false
      t.string :title
      t.text :action
      t.decimal :value, precision: 12, scale: 2
      t.string :status, null: false    # feito | ignorado
      t.jsonb :before, default: {}, null: false
      t.references :user, type: :uuid, foreign_key: true
      t.datetime :decided_at, null: false
      t.timestamps
    end
    add_index :ml_ad_decisions, [ :ml_account_id, :key, :signal, :decided_at ]
  end
end
