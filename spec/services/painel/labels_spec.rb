require "rails_helper"

RSpec.describe Painel::Labels do
  it "traduz os status da SPEC" do
    expect(described_class.status("active")).to eq("Ativo")
    expect(described_class.status("under_review")).to eq("Em revisão")
    expect(described_class.status("inactive")).to eq("Inativo")
  end

  it "traduz o tipo de anúncio a partir da letra ou do listing_type_id do ML" do
    expect(described_class.listing_type("P")).to eq("Premium")
    expect(described_class.listing_type("gold_special")).to eq("Clássico")
    expect(described_class.listing_type(nil)).to be_nil
  end

  it "monta os links do anúncio publicado e do painel do vendedor" do
    expect(described_class.links("MLB1000000001")).to eq(
      public: "https://produto.mercadolivre.com.br/MLB-1000000001",
      seller_panel: "https://www.mercadolivre.com.br/anuncios/lista?search=MLB1000000001"
    )
  end
end
