require "rails_helper"

RSpec.describe Ml::ReturnInvoicesArchiveJob, type: :job do
  let(:account) { create(:ml_account, seller_id: 430) }
  let(:ml) { "https://api.mercadolibre.com" }

  # ZIP mínimo, sem compressão (método 0), para o leitor sem gem.
  def zip(files)
    local = "".b
    central = "".b
    files.each do |name, data|
      n = name.b
      d = data.b
      crc = Zlib.crc32(d)
      offset = local.bytesize
      local << [ 0x04034b50, 20, 0, 0, 0, 0, crc, d.bytesize, d.bytesize, n.bytesize, 0 ].pack("VvvvvvVVVvv") << n << d
      central << [ 0x02014b50, 20, 20, 0, 0, 0, 0, crc, d.bytesize, d.bytesize, n.bytesize, 0, 0, 0, 0, 0, offset ].pack("VvvvvvvVVVvvvvvVV") << n
    end
    local + central + [ 0x06054b50, 0, 0, files.size, files.size, central.bytesize, local.bytesize, 0 ].pack("VvvvvVVv")
  end

  def xml(number, fin: "4")
    %(<nfeProc><NFe><infNFe Id="NFe4226063292486000010855001000#{number}1999992491"><ide><natOp>Devolucao de mercadorias</natOp><serie>1</serie>) +
      %(<nNF>#{number}</nNF><dhEmi>2026-06-16T15:04:36-03:00</dhEmi><finNFe>#{fin}</finNFe><NFref><refNFe>4226</refNFe></NFref></ide></infNFe></NFe></nfeProc>)
  end

  it "acha no download em lote as notas de devolução do Full que a consulta por envio não acha, e não relê meses passados" do
    travel_to(Time.zone.local(2026, 7, 20, 12)) do
      allow(Ml::OAuth).to receive(:refresh!)
      MlOrder.create!(order_id: 2000016228169414, ml_account: account, status: "paid", date_created: 2.months.ago, total_amount: 100,
                      shipment: { "logistic_type" => "fulfillment" })
      claim = MlClaim.create!(ml_account: account, claim_id: 1, claim_type: "mediations", stage: "dispute", status: "closed",
                              order_id: 2000016228169414, date_created: 50.days.ago,
                              devolution: { "status" => "delivered", "date_closed" => "2026-05-11T10:29:24-04:00" })
      body = zip("xml/2000016228169414 - NFE - 6310468356.xml" => xml(11298), "xml/2000099 - NFE - 1.xml" => xml(5, fin: "1"))
      create = stub_request(:post, "#{ml}/archives").to_return(status: 201, body: { archive_id: "A1", status: "PROCESSING" }.to_json)
      stub_request(:get, "#{ml}/archives/A1").with(query: hash_including(process_name: "invoice-bra"))
        .to_return(status: 200, body: { archive_id: "A1", status: "READY", zip_ids: [ 9 ] }.to_json)
      stub_request(:get, "#{ml}/archives/A1/download").with(query: hash_including(zip_id: "9")).to_return(status: 200, body: body)

      result = described_class.run(account, sleeper: ->(_) { })

      expect(result[:months]).to eq(%w[2026-05 2026-06 2026-07]) # do fechamento da devolução até hoje (máx. 3 meses depois)
      expect(claim.reload.return_invoice).to include("label" => "011298-1", "source" => "ml")
      expect(account.reload.return_invoice_months).to eq(%w[2026-05 2026-06]) # o mês corrente é relido no dia seguinte
      expect(create).to have_been_requested.times(3)
      expect(described_class.run(account, sleeper: ->(_) { })[:months]).to eq([]) # já tem nota: nada a buscar
    end
  end
end
