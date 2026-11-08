require "rails_helper"

RSpec.describe "Mensagens (/api/messages)", type: :request do
  let(:company) { create(:company) }
  let(:member) { create(:user, company: company) }
  let(:admin) { create(:user, :admin, company: company) }
  let(:account) { create(:ml_account, company: company, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }

  def ml_message(id, from, to, text, at)
    { id: id, from: { user_id: from }, to: { user_id: to }, text: text, status: "available",
      message_date: { created: at, read: nil }, message_moderation: { status: "clean" } }
  end

  def stub_pack(pack, messages, status: "active", substatus: nil)
    stub_request(:get, %r{#{ml}/messages/packs/#{pack}/sellers/430\?})
      .to_return(status: 200, body: { paging: { total: messages.size }, messages: messages, seller_max_message_length: 350,
                                      conversation_status: { status: status, substatus: substatus, claim_ids: [] } }.to_json)
  end

  before do
    allow(Ml::OAuth).to receive(:refresh!)
    MlOrder.create!(order_id: 10, ml_account: account, status: "paid", date_created: 2.days.ago, total_amount: 50, buyer_nickname: "COMPRA1")
    MlOrderItem.create!(order_id: 10, item_id: "MLB1", sku: "S", title: "Secador", quantity: 1, unit_price: 50, sale_fee: 5)
  end

  describe Ml::Sync::Messages do
    let(:client) { Ml::Client.new(access_token: "tok", sleeper: ->(_) { }) }

    it "importa as conversas das vendas sem marcar como lidas e marca a venda como conferida" do
      stub_request(:get, %r{#{ml}/messages/unread}).to_return(status: 200, body: { results: [] }.to_json)
      read = stub_pack(10, [ ml_message("a", 99, 430, "Chegou quebrado", "2026-11-07T10:00:00Z") ])

      described_class.call(client, account)

      conv = account.ml_conversations.sole
      expect(conv).to have_attributes(pack_id: 10, buyer_id: 99, status: "active", last_from: "buyer", unread_count: 1, seller_max_length: 350)
      expect(read.with(query: hash_including(mark_as_read: "false"))).to have_been_requested
      expect(MlOrder.find_by(order_id: 10).messages_checked_at).to be_present
    end
  end

  it "lista primeiro as que aguardam o vendedor e envia a mensagem (admin, confirmação, até 350 caracteres)" do
    account.ml_conversations.create!(pack_id: 10, buyer_id: 99, status: "active", messages_count: 1, last_from: "buyer",
                                     last_message_at: 1.hour.ago, seller_max_length: 350,
                                     messages: [ { "id" => "a", "from" => 99, "to" => 430, "text" => "Chegou quebrado", "date" => "2026-11-07T10:00:00Z" } ])

    get "/api/messages", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["counts"]).to eq("aguardando" => 1, "todas" => 1)
    c = json["conversations"].first
    expect(c).to include("pack_id" => 10, "can_send" => true, "awaiting" => true)
    expect(c["order"]["items"].first["title"]).to eq("Secador")
    expect(c["messages"].first).to include("mine" => false, "text" => "Chegou quebrado")

    post "/api/messages/10/send", params: { account_id: account.id, text: "Olá! Vamos resolver.", confirm: true }, headers: auth_headers(member)
    expect(response).to have_http_status(:forbidden)
    post "/api/messages/10/send", params: { account_id: account.id, text: "x" * 351, confirm: true }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)

    sent = stub_request(:post, %r{#{ml}/messages/packs/10/sellers/430})
      .with(body: { from: { user_id: 430 }, to: { user_id: 99 }, text: "Olá! Vamos resolver." }.to_json).to_return(status: 200, body: "{}")
    stub_pack(10, [ ml_message("a", 99, 430, "Chegou quebrado", "2026-11-07T10:00:00Z"), ml_message("b", 430, 99, "Olá! Vamos resolver.", "2026-11-07T11:00:00Z") ])

    post "/api/messages/10/send", params: { account_id: account.id, text: "Olá! Vamos resolver.", confirm: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(sent).to have_been_requested.once
    expect(json["conversation"]).to include("awaiting" => false)
    expect(account.ml_message_sends.sole).to have_attributes(ok: true)
  end

  it "conversa bloqueada pelo ML não envia" do
    account.ml_conversations.create!(pack_id: 10, buyer_id: 99, status: "blocked", substatus: "blocked_by_cancelled_order", messages_count: 1, last_from: "buyer")

    post "/api/messages/10/send", params: { account_id: account.id, text: "Oi", confirm: true }, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["errors"].first).to include("pedido cancelado")
  end

  it "respostas padrão de mensagem ficam separadas e limitadas a 350 caracteres" do
    post "/api/question_templates", params: { account_id: account.id, kind: "mensagem", title: "Longa", body: "x" * 351 }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
    post "/api/question_templates", params: { account_id: account.id, kind: "mensagem", title: "Envio", body: "Seu pedido já foi enviado!" }, headers: auth_headers(admin)
    expect(response).to have_http_status(:created)

    get "/api/question_templates", params: { account_id: account.id, kind: "mensagem" }, headers: auth_headers(member)
    expect(json["templates"].map { |t| t["title"] }).to eq([ "Envio" ])
    get "/api/question_templates", params: { account_id: account.id }, headers: auth_headers(member)
    expect(json["templates"]).to eq([])
  end
end
