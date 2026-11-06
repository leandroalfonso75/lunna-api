# Importa o relatório de liberações do Mercado Pago (o extrato da conta: cada crédito e débito e o saldo), que o MP
# gera toda semana (agendado). Baixa os arquivos ainda não lidos dos últimos BACKFILL dias e grava cada linha uma vez
# (`line_key`: o mesmo movimento pode aparecer em dois relatórios). O CSV usa ';' e campos com JSON entre aspas
# que o CSV do Ruby recusa; por isso a leitura é por split nas colunas conhecidas.
module Mp
  module Sync
    module ReleaseReports
      BACKFILL = 120.days
      MAX_FILES = 6
      COLUMNS = %w[DATE SOURCE_ID EXTERNAL_REFERENCE RECORD_TYPE DESCRIPTION NET_CREDIT_AMOUNT NET_DEBIT_AMOUNT GROSS_AMOUNT
                   MP_FEE_AMOUNT FINANCING_FEE_AMOUNT SHIPPING_FEE_AMOUNT COUPON_AMOUNT PAYMENT_METHOD SHIPPING_ID ORDER_ID PACK_ID BALANCE_AMOUNT].freeze

      Result = Struct.new(:count, :files, :notes, keyword_init: true)

      def self.call(client, account, now: Time.current)
        done = account.mp_release_lines.distinct.pluck(:file_name).to_set
        files = Array(client.release_reports)
          .select { |f| f["status"].to_s == "enabled" && f["file_name"].present? && Time.zone.parse(f["end_date"].to_s).to_i >= (now - BACKFILL).to_i }
          .reject { |f| done.include?(f["file_name"]) }
          .sort_by { |f| f["begin_date"].to_s }
          .first(MAX_FILES)
        count = 0
        files.each { |f| count += import(account, f["file_name"], client.release_report(f["file_name"])) }
        account.update_columns(mp_releases_synced_at: now)
        Result.new(count: count, files: files.size, notes: [])
      rescue Mp::Client::Error => e
        Result.new(count: count.to_i, files: 0, notes: [ "Mercado Pago (liberações): #{e.message.truncate(160)}" ])
      end

      def self.import(account, file_name, body)
        lines = body.lines.map(&:chomp).reject(&:blank?)
        return 0 if lines.empty?

        header = lines.first.split(";")
        idx = COLUMNS.to_h { |c| [ c, header.index(c) ] }
        n = 0
        lines.drop(1).each do |line|
          cols = line.split(";")
          v = ->(name) { idx[name] ? cols[idx[name]].to_s.strip : "" }
          next if v.("RECORD_TYPE") == "total"

          num = ->(name) { v.(name).presence&.tr(",", ".")&.to_f || 0.0 }
          big = ->(name) { v.(name)[/\A\d+\z/]&.to_i }
          attrs = {
            ml_account_id: account.id, file_name: file_name, line_key: Digest::SHA1.hexdigest([ v.("DATE"), v.("SOURCE_ID"), v.("RECORD_TYPE"), v.("DESCRIPTION"), v.("NET_CREDIT_AMOUNT"), v.("NET_DEBIT_AMOUNT"), v.("BALANCE_AMOUNT") ].join("|")),
            date: v.("DATE").presence, source_id: big.("SOURCE_ID"), external_reference: v.("EXTERNAL_REFERENCE").presence,
            record_type: v.("RECORD_TYPE").presence, description: v.("DESCRIPTION").presence,
            net_credit: num.("NET_CREDIT_AMOUNT"), net_debit: num.("NET_DEBIT_AMOUNT"), gross: num.("GROSS_AMOUNT"),
            mp_fee: num.("MP_FEE_AMOUNT"), financing_fee: num.("FINANCING_FEE_AMOUNT"), shipping_fee: num.("SHIPPING_FEE_AMOUNT"),
            coupon_amount: num.("COUPON_AMOUNT"), balance: v.("BALANCE_AMOUNT").presence&.to_f,
            order_id: big.("ORDER_ID"), shipping_id: big.("SHIPPING_ID"), pack_id: big.("PACK_ID"), payment_method: v.("PAYMENT_METHOD").presence,
            created_at: Time.current, updated_at: Time.current
          }
          MpReleaseLine.upsert(attrs, unique_by: %i[ml_account_id line_key], update_only: %i[file_name])
          n += 1
        end
        n
      end
    end
  end
end
