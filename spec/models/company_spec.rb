require "rails_helper"

RSpec.describe Company, type: :model do
  it "é válida com os defaults da factory" do
    expect(build(:company)).to be_valid
  end

  it "exige name" do
    company = build(:company, name: nil)

    expect(company).not_to be_valid
    expect(company.errors[:name]).to be_present
  end

  it "exige tax_pct entre 0 e 100" do
    expect(build(:company, tax_pct: -0.1)).not_to be_valid
    expect(build(:company, tax_pct: 100.1)).not_to be_valid
    expect(build(:company, tax_pct: 0)).to be_valid
    expect(build(:company, tax_pct: 100)).to be_valid
  end

  it "exige min_margin_pct entre 0 e 100" do
    expect(build(:company, min_margin_pct: -0.1)).not_to be_valid
    expect(build(:company, min_margin_pct: 100.1)).not_to be_valid
  end

  it "exige abc_cut_a > 0" do
    expect(build(:company, abc_cut_a: 0)).not_to be_valid
  end

  it "exige abc_cut_b <= 100" do
    expect(build(:company, abc_cut_b: 100.1)).not_to be_valid
    expect(build(:company, abc_cut_b: 100)).to be_valid
  end

  it "exige abc_cut_a < abc_cut_b" do
    company = build(:company, abc_cut_a: 95, abc_cut_b: 80)

    expect(company).not_to be_valid
    expect(company.errors[:abc_cut_a]).to be_present
  end

  it "aceita abc_cut_a igual a abc_cut_b como inválido (não é menor)" do
    expect(build(:company, abc_cut_a: 80, abc_cut_b: 80)).not_to be_valid
  end

  it "exige group_up_pct >= 0" do
    expect(build(:company, group_up_pct: -0.1)).not_to be_valid
    expect(build(:company, group_up_pct: 0)).to be_valid
  end

  it "exige group_down_pct <= 0" do
    expect(build(:company, group_down_pct: 0.1)).not_to be_valid
    expect(build(:company, group_down_pct: 0)).to be_valid
  end

  describe "ai_model (id OpenRouter, DECISOES §10)" do
    it "aceita ids no formato fornecedor/modelo" do
      expect(build(:company, ai_model: "anthropic/claude-sonnet-4.5")).to be_valid
      expect(build(:company, ai_model: "openai/gpt-4o:online")).to be_valid
    end

    it "rejeita sem barra, com espaço, ou muito longo" do
      expect(build(:company, ai_model: "claude")).not_to be_valid
      expect(build(:company, ai_model: "a b/c")).not_to be_valid
      expect(build(:company, ai_model: "f/#{'m' * 119}")).not_to be_valid # 121 chars, formato válido
    end

    it "vazio normaliza para nil (é opcional)" do
      company = create(:company, ai_model: "  ")

      expect(company.ai_model).to be_nil
    end
  end

  describe "openrouter_api_key" do
    it "fica cifrada no banco (a coluna bruta não é a chave)" do
      company = create(:company, :with_ai)

      raw_value = ActiveRecord::Base.connection.select_value(
        "SELECT openrouter_api_key FROM companies WHERE id = #{ActiveRecord::Base.connection.quote(company.id)}"
      )

      expect(raw_value).to be_present
      expect(raw_value).not_to eq(company.openrouter_api_key)
      expect(company.reload.openrouter_api_key).to eq("sk-or-v1-fake-key-1234")
    end
  end

  describe "#ai_configured?" do
    it "só é true com chave e modelo" do
      expect(build(:company)).not_to be_ai_configured
      expect(build(:company, openrouter_api_key: "chave")).not_to be_ai_configured
      expect(build(:company, ai_model: "anthropic/claude-sonnet-4.5")).not_to be_ai_configured
      expect(build(:company, :with_ai)).to be_ai_configured
    end
  end

  describe "#ai_key_hint" do
    it "mostra só os 4 últimos caracteres da chave" do
      company = build(:company, openrouter_api_key: "sk-or-v1-abcdef1234")

      expect(company.ai_key_hint).to eq("…1234")
    end

    it "é nil sem chave" do
      expect(build(:company).ai_key_hint).to be_nil
    end
  end
end
