class AddHiddenToOlistProducts < ActiveRecord::Migration[8.1]
  def change
    # Produto removido da seção Produtos pelo usuário: some da lista (mantido ou excluído no Olist); a sincronização
    # não mexe nestas colunas, então ele não volta.
    add_column :olist_products, :hidden_at, :datetime
    add_column :olist_products, :hidden_by_user_id, :uuid
    add_index :olist_products, [ :company_id, :hidden_at ]
  end
end
