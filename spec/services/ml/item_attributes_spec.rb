require "rails_helper"

RSpec.describe Ml::ItemAttributes do
  let(:account) { create(:ml_account, seller_id: 430_014_725) }
  let(:entries) { JSON.parse(ml_fixture("items_multiget")) }
  let(:item1) { entries[0]["body"] } # seller_custom_field no item
  let(:item2) { entries[1]["body"] } # SELLER_SKU só no atributo do item
  let(:item3) { entries[2]["body"] } # SELLER_SKU só na 1ª variação
  let(:item4) { entries[3]["body"] } # sem SKU em lugar nenhum

  describe "SKU (SPEC 3)" do
    it "usa o seller_custom_field do item quando presente" do
      expect(described_class.from(item1, account)[:sku]).to eq("LUN-001")
    end

    it "cai pro atributo SELLER_SKU do item quando falta o seller_custom_field" do
      expect(described_class.from(item2, account)[:sku]).to eq("LUN-002")
    end

    it "cai pro seller_custom_field/SELLER_SKU da primeira variação por último" do
      expect(described_class.from(item3, account)[:sku]).to eq("LUN-003-BR")
    end

    it "nil quando não tem SKU em lugar nenhum" do
      expect(described_class.from(item4, account)[:sku]).to be_nil
    end
  end

  describe "logistic_type (Full é derivado depois, aqui só guarda o valor bruto)" do
    it "guarda shipping.logistic_type sem transformar" do
      expect(described_class.from(item1, account)[:logistic_type]).to eq("fulfillment")
      expect(described_class.from(item2, account)[:logistic_type]).to eq("cross_docking")
    end
  end

  describe "free_shipping, variations_count, pictures_count, has_video" do
    it "lê shipping.free_shipping, conta variações/fotos e detecta vídeo pelo video_id" do
      attrs = described_class.from(item1, account)

      expect(attrs[:free_shipping]).to be true
      expect(attrs[:variations_count]).to eq(0)
      expect(attrs[:pictures_count]).to eq(7)
      expect(attrs[:has_video]).to be true
    end

    it "sem video_id não conta como tendo vídeo" do
      expect(described_class.from(item2, account)[:has_video]).to be false
    end
  end

  describe "brand/model" do
    it "lê dos atributos BRAND/MODEL" do
      attrs = described_class.from(item1, account)

      expect(attrs[:brand]).to eq("Lunna")
      expect(attrs[:model]).to eq("Aurora")
    end
  end

  describe "attrs_filled" do
    it "conta atributo com value_id, value_name ou values presentes, e ignora o totalmente vazio" do
      ids = described_class.from(item1, account)[:attrs_filled]

      expect(ids).to contain_exactly("BRAND", "MODEL", "COLOR", "SELLER_SKU")
      expect(ids).not_to include("GTIN")
    end

    it "inclui attribute_combinations e attributes das variações, sem duplicar" do
      ids = described_class.from(item3, account)[:attrs_filled]

      expect(ids).to contain_exactly("BRAND", "COLOR", "SELLER_SKU")
    end
  end

  it "carrega item_id, ml_account_id e seller_id a partir do body e da conta" do
    attrs = described_class.from(item1, account)

    expect(attrs[:item_id]).to eq("MLB1000000001")
    expect(attrs[:ml_account_id]).to eq(account.id)
    expect(attrs[:seller_id]).to eq(430_014_725)
  end

  describe "inventory_refs (estoque Full)" do
    it "pega o inventory_id do item com o SKU dele" do
      body = { "id" => "MLB1", "seller_custom_field" => "SKU-1", "inventory_id" => "INV1" }
      expect(described_class.from(body, account)[:inventory_refs]).to eq([ { "sku" => "SKU-1", "inventory_id" => "INV1" } ])
    end

    it "pega o inventory_id de cada variação com o SKU dela (ou o do item)" do
      body = {
        "id" => "MLB2", "seller_custom_field" => "BASE",
        "variations" => [
          { "inventory_id" => "V1", "seller_custom_field" => "BASE-P" },
          { "inventory_id" => "V2" },
          { "seller_custom_field" => "SEM-INVENTORY" }
        ]
      }
      expect(described_class.from(body, account)[:inventory_refs]).to eq([
        { "sku" => "BASE-P", "inventory_id" => "V1" }, { "sku" => "BASE", "inventory_id" => "V2" }
      ])
    end

    it "vazio quando não é Full" do
      expect(described_class.from({ "id" => "MLB3" }, account)[:inventory_refs]).to eq([])
    end
  end
end
