require "rails_helper"

# Atualização automática das fichas vindas do ERP (27/11/2026).
RSpec.describe Erp::CatalogRefresh do
  let(:company) { create(:company) }
  let!(:connection) { create(:olist_connection, company: company) }
  let(:importer) { Class.new { def self.call(_c, erp_ids:) = (@ids = erp_ids); def self.ids = @ids } }

  def mirror(id, updated:, parent: nil, status: "A")
    OlistProduct.create!(company: company, olist_id: id, sku: "S#{id}", description: "P#{id}", kind: "S", status: status, parent_olist_id: parent,
                         olist_updated_at: updated, synced_at: Time.current)
  end

  def ficha(id, synced:) = company.catalog_products.create!(kind: "simple", source: "erp", erp_key: "olist", erp_id: id, name: "F#{id}", erp_synced_at: synced)

  it "reimporta o que mudou no ERP depois da última importação (inclusive só uma variação) e importa os ativos novos" do
    mirror(1, updated: 2.days.ago); ficha(1, synced: 1.day.ago)               # sem mudança
    mirror(2, updated: 1.hour.ago); ficha(2, synced: 1.day.ago)               # o produto mudou
    mirror(3, updated: 3.days.ago); ficha(3, synced: 1.day.ago)
    mirror(31, updated: 1.hour.ago, parent: 3)                                 # só a variação mudou
    mirror(4, updated: 1.day.ago)                                              # novo, ainda sem ficha
    mirror(5, updated: 1.hour.ago, status: "E")                                # excluído: fica fora

    expect(described_class.call(company, importer: importer)).to contain_exactly(2, 3, 4)
    expect(importer.ids).to contain_exactly(2, 3, 4)
  end

  it "empresa que ainda não migrou não importa nada sozinha" do
    mirror(4, updated: 1.day.ago)
    expect(described_class.call(company, importer: importer)).to eq([])
  end
end
