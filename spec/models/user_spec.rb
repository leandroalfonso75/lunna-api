require "rails_helper"

RSpec.describe User, type: :model do
  it "é válido com os defaults da factory" do
    expect(build(:user)).to be_valid
  end

  it "normaliza o e-mail (strip + downcase)" do
    user = create(:user, email: "  Fulano@Example.com  ")

    expect(user.email).to eq("fulano@example.com")
  end

  it "exige e-mail único" do
    create(:user, email: "dup@example.com")
    other = build(:user, email: "DUP@example.com")

    expect(other).not_to be_valid
    expect(other.errors[:email]).to be_present
  end

  it "exige e-mail em formato válido" do
    expect(build(:user, email: "não-é-email")).not_to be_valid
  end

  it "exige senha com no mínimo 8 caracteres na criação" do
    expect(build(:user, password: "1234567")).not_to be_valid
    expect(build(:user, password: "12345678")).to be_valid
  end

  it "não exige senha mínima quando não está sendo alterada" do
    user = create(:user, password: "password123")

    user.name = "Outro nome"

    expect(user).to be_valid
  end

  it "exige role em admin|member" do
    expect(build(:user, role: "root")).not_to be_valid
    expect(build(:user, role: "admin")).to be_valid
    expect(build(:user, role: "member")).to be_valid
  end

  describe "#admin?" do
    it "é true só pra role admin" do
      expect(build(:user, :admin)).to be_admin
      expect(build(:user, role: "member")).not_to be_admin
    end
  end
end
