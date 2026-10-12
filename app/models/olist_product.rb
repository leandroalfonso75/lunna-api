# Cópia local de um produto do Olist ERP, mantida pela sincronização
# (Olist::SyncProducts). A fonte da verdade continua sendo o Olist.
class OlistProduct < ApplicationRecord
  belongs_to :company

  scope :search, lambda { |term|
    next all if term.blank?

    like = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("description ILIKE :q OR sku ILIKE :q OR gtin ILIKE :q", q: like)
  }
end
