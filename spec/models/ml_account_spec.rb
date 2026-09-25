require "rails_helper"

RSpec.describe MlAccount, type: :model do
  describe "tokens criptografados" do
    it "grava access_token e refresh_token cifrados na coluna (valor bruto ≠ token)" do
      account = create(:ml_account, access_token: "APP_USR-segredo", refresh_token: "TG-segredo")

      id = MlAccount.connection.quote(account.id)
      raw_access = MlAccount.connection.select_value("select access_token from ml_accounts where id = #{id}")
      raw_refresh = MlAccount.connection.select_value("select refresh_token from ml_accounts where id = #{id}")

      expect(raw_access).not_to eq("APP_USR-segredo")
      expect(raw_refresh).not_to eq("TG-segredo")
      expect(account.reload.access_token).to eq("APP_USR-segredo")
      expect(account.reload.refresh_token).to eq("TG-segredo")
    end
  end
end
