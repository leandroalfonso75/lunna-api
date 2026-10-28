# Rotina das 03:00 da seção Promoções: cada execução (simulação ou aplicação real), com os totais; cada anúncio da
# execução fica em ml_promotion_actions (run_id), com o antes e o depois.
class CreateMlPromotionRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :ml_promotion_runs do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :mode, null: false             # simulation | apply
      t.string :trigger, null: false          # agendada | manual
      t.string :status, null: false, default: "running" # running | done | failed
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.jsonb :totals, null: false, default: {}
      t.string :error
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :ml_promotion_runs, %i[ml_account_id started_at]

    add_reference :ml_promotion_actions, :run, foreign_key: { to_table: :ml_promotion_runs, on_delete: :cascade }
    add_column :ml_promotion_actions, :from_profit, :decimal, precision: 12, scale: 2
    add_column :ml_promotion_actions, :to_profit, :decimal, precision: 12, scale: 2

    add_column :companies, :promo_routine_enabled, :boolean, null: false, default: false
    add_column :companies, :promo_routine_mode, :string, null: false, default: "simulation"
  end
end
