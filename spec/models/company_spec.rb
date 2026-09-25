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
end
