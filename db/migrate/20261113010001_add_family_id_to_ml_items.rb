# Curva ABC (pedido do usuário em 13/11/2026): "aplicar às demais variações do anúncio" precisa saber quais anúncios são
# variações do mesmo anúncio pai. No modelo de User Products do ML cada variação é um anúncio (MLB) próprio e o pai é a
# família (`family_id` do item).
class AddFamilyIdToMlItems < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_items, :family_id, :string
    add_index :ml_items, %i[ml_account_id family_id]
  end
end
