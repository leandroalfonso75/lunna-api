# Edição da ficha vinda do ERP (28/11/2026): campos salvos "apenas no Lunna" ficam marcados com o valor do ERP, para a
# atualização automática e o "Reimportar do ERP" não os sobrescreverem em silêncio (e a tela poder voltar ao do ERP).
class AddLocalOverridesToCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_products, :local_overrides, :jsonb, null: false, default: {}
  end
end
