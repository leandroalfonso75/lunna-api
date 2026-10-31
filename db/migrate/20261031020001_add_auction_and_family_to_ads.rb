class AddAuctionAndFamilyToAds < ActiveRecord::Migration[8.1]
  def change
    # Leilão por campanha (só o detalhe da campanha traz): impression share, perdas por orçamento e por classificação e
    # acos_benchmark, por janela ("7d", "7d_prev", "30d")
    add_column :ml_ad_campaigns, :auction, :jsonb, default: {}, null: false
    add_column :ml_ad_campaigns, :auction_synced_at, :datetime

    # Família (produto) e qualidade da imagem do anúncio, que a API devolve sem documentar
    add_column :ml_ad_items, :family_id, :string
    add_column :ml_ad_items, :family_name, :string
    add_column :ml_ad_items, :image_quality, :string
    add_column :ml_ad_items, :domain_id, :string
    add_index :ml_ad_items, [ :ml_account_id, :family_id ]
  end
end
