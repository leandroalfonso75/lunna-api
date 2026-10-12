class AddVariationLinksToOlistProducts < ActiveRecord::Migration[8.1]
  def change
    # Variação aponta para o produto pai (id do Olist). Quem sabe quais são as
    # variações é o pai (GET /produtos/{id}), então guardamos a lista nele e a
    # data de alteração em que ela foi lida, para só reler quando o pai mudar.
    add_column :olist_products, :parent_olist_id, :bigint
    add_column :olist_products, :variation_ids, :jsonb, null: false, default: []
    add_column :olist_products, :variations_source_updated_at, :datetime
    add_index :olist_products, [ :company_id, :parent_olist_id ]
  end
end
