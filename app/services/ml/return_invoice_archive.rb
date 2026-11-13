# Notas de devolução pelo "download em lote de documentos fiscais" do ML (POST /archives, process invoice-bra), mês a mês
# (correção de 13/11/2026). Em vendas mais antigas o ML não liga a nota de devolução ao envio da venda, então a consulta
# por envio só devolve a nota de venda; o lote traz todos os XMLs de devolução emitidos no período, com o número da venda
# no nome do arquivo ("2000016228169414 - NFE - 6310468356.xml"). Pedido de exportação: não altera nada na conta.
# Limites do ML: janela de até 31 dias e documentos de até 18 meses.
module Ml
  module ReturnInvoiceArchive
    BASE = "https://api.mercadolibre.com".freeze
    PROCESS = "invoice-bra".freeze
    VERSION = 2
    MAX_AGE_MONTHS = 17
    POLLS = 36
    POLL_WAIT = 5

    # => { order_id(Integer) => invoice hash (Ml::Sync::ReturnInvoices.build) } das notas de devolução do mês.
    def self.month(account, first_day, sleeper: ->(s) { sleep(s) })
      zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
      from = zone.local(first_day.year, first_day.month, 1)
      to = [ from + 1.month - 1.second, Time.current ].min
      http = Faraday.new(url: BASE) { |f| f.options.timeout = 90 }
      auth = { "Authorization" => "Bearer #{account.access_token}", "Content-Type" => "application/json" }
      body = { process_name: PROCESS, process_version: VERSION,
               body: { site: "MLB", start: from.utc.iso8601, end: to.utc.iso8601, type_of_receipt: [ "NFE" ], file_types: [ "xml" ],
                       status: [ "authorized" ], fiscal_data_transaction_type: [ "devolution" ] } }
      res = http.post("/archives", body.to_json, auth)
      raise Ml::Client::Error.new(status: res.status, path: "/archives", body: res.body.to_s[0, 300]) unless res.status.between?(200, 299)

      id = JSON.parse(res.body)["archive_id"]
      state = nil
      POLLS.times do
        st = http.get("/archives/#{id}", { process_name: PROCESS, version: VERSION }, auth)
        state = JSON.parse(st.body) rescue {}
        break unless state["status"] == "PROCESSING"

        sleeper.call(POLL_WAIT)
      end
      return {} if %w[EMPTY].include?(state["status"])
      raise Ml::Client::Error.new(status: nil, path: "/archives/#{id}", body: "lote #{state['status'] || 'sem resposta'}") unless state["status"] == "READY"

      Array(state["zip_ids"]).each_with_object({}) do |zip_id, map|
        zip = http.get("/archives/#{id}/download", { process_name: PROCESS, version: VERSION, zip_id: zip_id }, auth)
        next unless zip.status == 200

        ZipReader.entries(zip.body).each do |name, xml|
          order_id = File.basename(name)[/\A(\d{10,})\s*-/, 1]
          inv = parse(xml)
          map[order_id.to_i] = inv if order_id && inv
        end
      end
    end

    def self.parse(xml)
      text = xml.to_s.force_encoding("UTF-8")
      tag = ->(t) { text[%r{<#{t}>([^<]*)</#{t}>}, 1] }
      return nil unless tag.("finNFe") == "4" || tag.("natOp").to_s =~ /devolu/i

      key = text[/Id="NFe(\d{44})"/, 1]
      Ml::Sync::ReturnInvoices.build(tag.("nNF"), tag.("serie"), "ml", tag.("dhEmi"), key)
    end

    # Meses a buscar: os das devoluções do Full ainda sem nota (do fechamento da devolução até 3 meses depois, porque a
    # nota pode sair semanas depois), dentro do limite de idade do ML; meses passados já lidos não são lidos de novo.
    def self.months_for(account, claims, done)
      zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
      oldest = zone.today.beginning_of_month << MAX_AGE_MONTHS
      current = zone.today.beginning_of_month
      claims.flat_map do |c|
        closed = (c.devolution.to_h["date_closed"].presence || c.devolution.to_h["last_updated"].presence || c.date_created.iso8601)
        start = Time.zone.parse(closed.to_s).in_time_zone(zone).to_date.beginning_of_month
        (0..3).map { |i| start >> i }
      end.uniq.select { |m| m >= oldest && m <= current }
             .reject { |m| m < current && done.include?(m.strftime("%Y-%m")) }.sort
    end
  end
end
