require "rails_helper"

RSpec.describe "Mercado Pago (aba Repasses)" do
  let(:account) { create(:ml_account) }

  describe Mp::Sync::ReleaseReports do
    it "lê o relatório de liberações por ';', grava cada movimento uma vez e ignora a linha de total" do
      csv = <<~CSV
        DATE;SOURCE_ID;EXTERNAL_REFERENCE;RECORD_TYPE;DESCRIPTION;NET_CREDIT_AMOUNT;NET_DEBIT_AMOUNT;GROSS_AMOUNT;MP_FEE_AMOUNT;FINANCING_FEE_AMOUNT;SHIPPING_FEE_AMOUNT;TAXES_AMOUNT;COUPON_AMOUNT;PAYMENT_METHOD;SHIPPING_ID;ORDER_ID;PACK_ID;BALANCE_AMOUNT
        2026-10-01T00:00:00.000-03:00;;;initial_available_balance;;100.00;0.00;;;;;;;;;;;100.00
        2026-10-01T10:00:00.000-03:00;555;2000001;release;payment;75.50;0.00;100.00;-15.00;0.00;-9.50;0.00;0.00;pix;4801;2000001;;175.50
        2026-10-02T10:00:00.000-03:00;556;;release;payout;0.00;50.00;-50.00;0.00;0.00;0.00;0.00;0.00;;;;;125.50
        ;;;total;;175.50;50.00;;;;;;;;;;;
      CSV
      expect(described_class.import(account, "r1.csv", csv)).to eq(3)
      expect(described_class.import(account, "r2.csv", csv)).to eq(3) # o mesmo movimento em dois relatórios
      expect(account.mp_release_lines.count).to eq(3)
      sale = account.mp_release_lines.find_by(description: "payment")
      expect(sale).to have_attributes(source_id: 555, order_id: 2000001, shipping_id: 4801, net_credit: 75.5, balance: 175.5, amount: 75.5)
      expect(account.mp_release_lines.find_by(description: "payout").amount).to eq(-50.0)
    end
  end

  describe Mp::Sync::Payments do
    def charge(name, from, amount, type: "fee")
      { "name" => name, "type" => type, "accounts" => { "from" => from, "to" => "x" }, "amounts" => { "original" => amount, "refunded" => 0 } }
    end

    it "separa as taxas do vendedor e deixa de fora o juro de parcelamento pago pelo comprador" do
      raw = [
        charge("ml_sale_fee", "collector", 20), charge("mp_processing_fee", "collector", 1.5), charge("mp_financing_1x_fee", "collector", 0.1),
        charge("financing_fee", "collector", 9), charge("financing_transfer", "payer", 9),
        charge("shp_fulfillment", "collector", 26.74, type: "shipping"), charge("coupon_fee", "collector", 4, type: "coupon"),
        charge("coupon_code", "ml", 10, type: "coupon")
      ]
      expect(described_class.amounts(described_class.normalize(raw)))
        .to eq(ml_fee: 20.0, mp_fee: 1.5, financing_fee: 0.1, shipping_fee: 26.74, coupon_amount: 4.0, other_charges: 0.0)
    end

    it "lê cada janela inteira e grava o pagamento com a venda" do
      client = instance_double(Mp::Client)
      result = { "id" => 77, "order" => { "id" => "2000009" }, "status" => "approved", "transaction_amount" => 50,
                 "transaction_details" => { "net_received_amount" => 40 }, "date_last_updated" => Time.current.iso8601, "charges_details" => [] }
      allow(client).to receive(:payments).and_return({ "paging" => { "total" => 1 }, "results" => [ result ] })
      now = Time.current
      account.update_columns(mp_payments_synced_at: now - 1.day)

      described_class.call(client, account, now: now)

      expect(account.mp_payments.sole).to have_attributes(payment_id: 77, order_id: 2000009, net_received: 40)
      expect(account.reload.mp_payments_synced_at).to be_within(1.second).of(now)
    end
  end
end
