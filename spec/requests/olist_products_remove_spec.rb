require "rails_helper"

RSpec.describe "Excluir produtos (seção Produtos)", type: :request do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:member) { create(:user, company: company) }
  let(:base) { "https://api.tiny.com.br/public-api/v3" }
  let!(:parent) { create(:olist_product, company: company, olist_id: 100, sku: "PAI", description: "Secador", variation_kind: "P", status: "A") }
  let!(:variation) { create(:olist_product, company: company, olist_id: 101, sku: "PAI-110", variation_kind: "V", parent_olist_id: 100, status: "A") }
  let!(:simple) { create(:olist_product, company: company, olist_id: 200, sku: "DIF", description: "Difusor", status: "A") }

  before { create(:olist_connection, company: company) }

  def remove(ids, keep:, user: admin, confirm: true)
    post "/api/olist/products/remove", params: { ids: ids, keep_in_erp: keep, confirm: confirm }.compact, headers: auth_headers(user)
  end

  def listed_skus
    get "/api/olist/products", headers: auth_headers(admin)
    json["products"].map { |p| p["sku"] }
  end

  it "manter no ERP: some do Lunna (com as variações), não chama o Olist e a sincronização não traz de volta" do
    remove([ 100 ], keep: true)

    expect(response).to have_http_status(:ok)
    expect(json).to include("kept_in_erp" => true, "failed" => [])
    expect(json["removed"].map { |r| r["id"] }).to eq([ 100 ])
    expect(WebMock).not_to have_requested(:any, /api.tiny.com.br/)
    expect(OlistProduct.where(olist_id: [ 100, 101 ]).pluck(:hidden_at)).to all(be_present)
    expect(parent.reload.status).to eq("A") # cadastro no ERP intacto
    expect(listed_skus).to eq([ "DIF" ])

    # sincronização regrava o produto: hidden_at fica
    OlistProduct.upsert_all([ { company_id: company.id, olist_id: 100, sku: "PAI", description: "Secador novo", status: "A",
                                synced_at: Time.current, created_at: Time.current, updated_at: Time.current } ], unique_by: %i[company_id olist_id])
    expect(parent.reload).to have_attributes(description: "Secador novo", hidden_at: be_present)
  end

  it "não manter no ERP: exclui o cadastro no Olist, registra e some do Lunna; falha de um não impede o outro" do
    stub_request(:delete, "#{base}/produtos/200").to_return(status: 204, body: "")
    stub_request(:delete, "#{base}/produtos/100").to_return(status: 400, body: { mensagem: "Produto possui movimentações" }.to_json)

    remove([ 200, 100 ], keep: false)

    expect(response).to have_http_status(:ok)
    expect(json["removed"].map { |r| r["sku"] }).to eq([ "DIF" ])
    expect(json["failed"].first).to include("sku" => "PAI", "error" => a_string_including("Produto possui movimentações"))
    expect(simple.reload).to have_attributes(status: "E", hidden_at: be_present)
    expect(parent.reload.hidden_at).to be_nil
    changes = OlistChange.where(company: company).order(:created_at)
    expect(changes.map { |c| [ c.kind, c.olist_product_id, c.status ] }).to contain_exactly([ "delete", 200, "done" ], [ "delete", 100, "failed" ])
    expect(listed_skus).to eq([ "PAI" ])
  end

  it "produto que já não existe no Olist (404) conta como excluído" do
    stub_request(:delete, "#{base}/produtos/200").to_return(status: 404, body: "")

    remove([ 200 ], keep: false)

    expect(json["removed"].map { |r| r["id"] }).to eq([ 200 ])
    expect(OlistChange.last).to have_attributes(status: "done", error: "já não existia no Olist")
  end

  it "exige admin, confirm=true e a escolha explícita de manter ou não no ERP" do
    remove([ 200 ], keep: false, user: member)
    expect(response).to have_http_status(:forbidden)

    remove([ 200 ], keep: false, confirm: nil)
    expect(response).to have_http_status(:unprocessable_content)

    remove([ 200 ], keep: nil)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json["errors"].first).to include("keep_in_erp")

    expect(WebMock).not_to have_requested(:any, /api.tiny.com.br/)
    expect(OlistProduct.where.not(hidden_at: nil)).to be_empty
  end

  it "não mexe em produto de outra empresa" do
    other = create(:olist_product, olist_id: 999, sku: "OUTRA")

    remove([ 999 ], keep: true)

    expect(json["removed"]).to eq([])
    expect(other.reload.hidden_at).to be_nil
  end
end
