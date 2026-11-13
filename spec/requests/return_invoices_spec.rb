require "rails_helper"

RSpec.describe Ml::Sync::ReturnInvoices, type: :request do
  let(:company) { create(:company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }
  let(:ml) { "https://api.mercadolibre.com" }
  let(:member) { create(:user, company: company) }
  let(:olist) { instance_double(Olist::Client) }

  def order(id, logistic, ship: nil, doc: nil, name: nil)
    MlOrder.create!(order_id: id, ml_account: account, status: "paid", date_created: 10.days.ago, total_amount: 100, shipping_id: ship,
                    shipment: { "logistic_type" => logistic }, buyer_doc_number: doc, buyer_name: name)
    MlOrderItem.create!(order_id: id, item_id: "MLB1", sku: "SKU-#{id}", title: "Secador", quantity: 1, unit_price: 100, sale_fee: 10)
  end

  def claim(id, order_id, status: "delivered")
    MlClaim.create!(ml_account: account, claim_id: id, claim_type: "mediations", stage: "dispute", status: "closed", order_id: order_id,
                    resource: "order", resource_id: order_id, date_created: 5.days.ago, details_synced_at: Time.current,
                    devolution: { "status" => status, "shipments" => [ { "type" => "return", "shipment_id" => 9 } ] })
  end

  it "Full: nota de devolução do envio no ML; Agência: nota de entrada do Olist pelo CPF; sem nota fica SEM NOTA, com aba própria" do
    order(10, "fulfillment", ship: 700)
    order(11, "fulfillment", ship: 701)
    order(12, "xd_drop_off", doc: "123.456.789-00", name: "Maria Souza")
    order(13, "self_service", name: "José Lima")
    claim(1, 10); claim(2, 11); claim(3, 12); claim(4, 13)
    claim(5, 10, status: "shipped") # ainda não voltou: não consulta

    stub_request(:get, "#{ml}/users/430/invoices/shipments/700").to_return(status: 200, body: {
      invoice_number: 22615, invoice_series: "1", issued_date: "2026-11-03T20:46:37Z",
      fiscal_data: { transaction_type: "devolution" }, attributes: { invoice_key: "4226" }
    }.to_json)
    stub_request(:get, "#{ml}/users/430/invoices/shipments/701").to_return(status: 200, body: { invoice_number: 1, invoice_series: "1", fiscal_data: { transaction_type: "sale" } }.to_json)
    allow(olist).to receive(:entry_notes).and_return("itens" => [
      { "tipo" => "E", "numero" => "001215", "serie" => "2", "dataEmissao" => Date.current.iso8601, "chaveAcesso" => "x",
        "cliente" => { "nome" => "Outra Pessoa", "cpfCnpj" => "123.456.789-00" }, "itens" => [ { "codigo" => "SKU-12" } ] },
      { "tipo" => "E", "numero" => "000999", "serie" => "2", "dataEmissao" => 30.days.ago.to_date.iso8601, # antes da reclamação
        "cliente" => { "nome" => "José Lima", "cpfCnpj" => "" }, "itens" => [] }
    ])

    result = described_class.call(client, account, olist: olist)

    expect(result).to have_attributes(checked: 4, found: 2)
    expect(MlClaim.find_by(claim_id: 1).return_invoice).to include("label" => "022615-1", "source" => "ml")
    expect(MlClaim.find_by(claim_id: 3).return_invoice).to include("label" => "001215-2", "source" => "olist")
    expect(MlClaim.find_by(claim_id: 2).return_invoice).to be_nil
    expect(MlClaim.find_by(claim_id: 4).return_invoice).to be_nil # a nota do José é de antes da reclamação
    expect(described_class.pending(account).count).to eq(0) # conferidas: voltam só depois de 6 horas

    get "/api/claims/returns", params: { account_id: account.id }, headers: auth_headers(member)
    rows = json["tabs"].except("sem_nota").values.flatten.to_h { |r| [ r["claim_id"], r ] }
    expect(rows[1]["return_invoice"]).to include("state" => "com_nota", "label" => "022615-1")
    expect(rows[2]["return_invoice"]).to include("state" => "sem_nota", "label" => "SEM NOTA", "emit_link" => "https://www.mercadolivre.com.br/vendas/11/detalhe")
    expect(rows[4]["return_invoice"]).to include("state" => "sem_nota", "emit_link" => nil) # Flex: emite no ERP
    expect(rows[5]["return_invoice"]).to include("state" => "aguardando")
    expect(rows[1]["logistic"]).to eq("Full")
    expect(rows[3]["logistic"]).to eq("Agência")
    expect(json["tabs"]["sem_nota"].map { |r| r["claim_id"] }).to match_array([ 2, 4 ])
  end
end
