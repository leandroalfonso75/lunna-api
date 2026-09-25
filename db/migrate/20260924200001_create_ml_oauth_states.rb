class CreateMlOauthStates < ActiveRecord::Migration[8.1]
  def change
    # `id: false` suprime a coluna id automática; `primary_key: true` na
    # própria coluna `state` é quem efetivamente a marca como PK — passar só
    # `primary_key: "state"` no create_table (sem redeclarar a coluna assim)
    # não cria constraint nenhuma.
    create_table :ml_oauth_states, id: false do |t|
      t.string :state, primary_key: true
      t.references :company, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false
    end
  end
end
