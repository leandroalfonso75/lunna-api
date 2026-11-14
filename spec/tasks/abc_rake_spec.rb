require "rails_helper"
require "rake"

RSpec.describe "abc:descricao_ia" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "abc:descricao_ia" } }

  it "marca as sugestões de descrição como feitas no anúncio e nas variações da mesma família com SKU da ficha" do
    account = create(:ml_account)
    create(:ml_item, ml_account: account, item_id: "MLB1", family_id: "F1", sku: "TOM-01")
    create(:ml_item, ml_account: account, item_id: "MLB2", family_id: "F1", sku: "TOM-02")
    create(:ml_item, ml_account: account, item_id: "MLB4", family_id: "F1", sku: "TOM-ANTIGO") # mesma família, fora da ficha
    create(:ml_item, ml_account: account, item_id: "MLB3", family_id: "F2", sku: "TOM-02")

    expect { Rake::Task["abc:descricao_ia"].invoke("MLB1", "TOM-01 TOM-02") }.to output(/2 anúncio/).to_stdout
    expect(account.abc_suggestion_acks.distinct.pluck(:item_id)).to contain_exactly("MLB1", "MLB2")
    expect(account.abc_suggestion_acks.where(item_id: "MLB2").pluck(:key, :kind)).to include([ "descrição:Deixar a descrição mais chamativa", "feita" ])
  end
end
