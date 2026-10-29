class AddPromoAutomationRules < ActiveRecord::Migration[8.1]
  def change
    # Promoções: permitir reduzir a margem ao buscar a mínima (e até quanto) e incluir anúncios de catálogo na automação
    add_column :companies, :promo_allow_margin_drop, :boolean, default: false, null: false
    add_column :companies, :promo_margin_drop_tolerance, :decimal, precision: 5, scale: 2
    add_column :companies, :promo_include_catalog, :boolean, default: false, null: false

    # Catálogo: produto do catálogo e relação com o anúncio tradicional (sincronização)
    add_column :ml_items, :catalog_product_id, :string
    add_column :ml_items, :item_relations, :jsonb, default: [], null: false

    # Depois de mudar o preço de um anúncio de catálogo: confere se está ganhando; se não, volta ao preço anterior e
    # confere de novo; sem ganhar ainda, fica para análise manual (aviso na tela).
    create_table :ml_catalog_checks do |t|
      t.references :ml_account, type: :uuid, null: false, foreign_key: true
      t.string :item_id, null: false
      t.references :action, foreign_key: { to_table: :ml_promotion_actions }
      t.string :status, null: false, default: "aguardando" # aguardando | ganhando | revertido | analise_manual | resolvido
      t.integer :attempts, null: false, default: 0
      t.string :ml_status
      t.string :message
      t.datetime :check_at
      t.datetime :checked_at
      t.timestamps
    end
    add_index :ml_catalog_checks, [ :ml_account_id, :status ]
  end
end
