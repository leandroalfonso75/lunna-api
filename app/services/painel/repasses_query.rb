# Seção Financeiro, aba Repasses (pedido do usuário em 06/11/2026): conciliação geral com a conta do Mercado Pago.
# Para cada venda do período (agrupada por envio, porque o carrinho tem uma etiqueta só) cruza quatro pernas:
#   1. previsto no Lunna: receita − tarifa − frete do vendedor;
#   2. faturado pelo ML: tarifa e frete do extrato de faturamento (ml_billing_charges);
#   3. descontado no pagamento do Mercado Pago: taxas item a item e o líquido (mp_payments);
#   4. creditado na conta: a liberação no relatório de liberações (mp_release_lines).
# Também resume todos os movimentos da conta no período (entradas, saídas, saques, reservas) com o período anterior.
module Painel
  class RepassesQuery
    TOLERANCE = 0.05
    STATUS = {
      "conferido" => [ "Conferido", "ok" ], "frete_liberacao" => [ "Conferido (frete descontado na liberação)", "ok" ],
      "cupom" => [ "Cupom com participação do vendedor", "warn" ], "frete_nao_cobrado" => [ "Frete previsto que o ML não cobrou", "warn" ],
      "reembolso" => [ "Reembolsada / cancelada", "neutral" ], "mediacao" => [ "Em mediação", "warn" ],
      "sem_pagamento" => [ "Pagamento não localizado", "warn" ], "diferenca" => [ "Diferença a verificar", "bad" ]
    }.freeze
    CREDIT = {
      "creditado" => [ "Creditado", "ok" ], "a_liberar" => [ "A liberar", "neutral" ], "aguardando_relatorio" => [ "Liberado, aguardando relatório", "neutral" ],
      "nao_localizado" => [ "Não localizado no extrato", "bad" ], "sem_credito" => [ "Sem crédito", "neutral" ]
    }.freeze
    SALE_DESCRIPTIONS = %w[payment shipping].freeze

    def self.call(...) = new(...).call

    def initialize(account, rows, from, to, prev_from, prev_to, zone:)
      @account = account
      @rows = rows
      @from, @to, @prev_from, @prev_to = from, to, prev_from, prev_to
      @zone = zone
    end

    def call
      lines_until = @account.mp_release_lines.maximum(:date)
      {
        coverage: { payments_synced_at: @account.mp_payments_synced_at, releases_until: lines_until&.iso8601,
                    payments_from: @account.mp_payments.minimum(:date_created)&.iso8601, releases_from: @account.mp_release_lines.minimum(:date)&.iso8601,
                    releases_cover_period: lines_until.present? && lines_until >= @to },
        **sales(lines_until),
        account: account_movements
      }
    end

    private

    # --- pernas por venda ---

    def sales(lines_until)
      groups = @rows.group_by { |r| r.dig(:shipping, :id) || "o#{r[:order_id]}" }
      order_ids = @rows.map { |r| r[:order_id] }
      ship_ids = @rows.filter_map { |r| r.dig(:shipping, :id) }.uniq
      payments = @account.mp_payments.where(order_id: order_ids + ship_ids).to_a
      by_order = payments.group_by(&:order_id)
      lines = @account.mp_release_lines.where(source_id: payments.map(&:payment_id)).to_a.group_by(&:source_id)
      billing = @account.ml_billing_charges.where(order_id: order_ids).or(@account.ml_billing_charges.where(shipment_id: ship_ids)).to_a
      bill_order = billing.group_by(&:order_id)
      bill_ship = billing.group_by(&:shipment_id)
      now = Time.current

      result = groups.map do |key, rs|
        sid = rs.first.dig(:shipping, :id)
        sale_pays = rs.flat_map { |r| Array(by_order[r[:order_id]]) }.reject { |p| p.description == "marketplace_shipment" }
        buyer_pays = sid ? Array(by_order[sid]).select { |p| p.description == "marketplace_shipment" } : []
        pays = sale_pays + buyer_pays
        approved = pays.select { |p| p.status == "approved" }
        e = ->(k) { rs.sum { |r| r[:economics][k].to_f } }
        expected = e.(:revenue) - e.(:fee) - e.(:shipping_cost)
        net = approved.sum { |p| p.net_received.to_f }
        coupon = approved.sum { |p| p.coupon_amount.to_f }
        sale_lines = approved.flat_map { |p| Array(lines[p.payment_id]).select { |l| SALE_DESCRIPTIONS.include?(l.description) } }
        credited = sale_lines.sum(&:amount)
        # no carrinho com frete na fatura, o pagamento não desconta a etiqueta e a liberação desconta: vale o creditado
        sale_ok = sale_pays.select { |p| p.status == "approved" }
        released = sale_ok.any? && sale_ok.all? { |p| Array(lines[p.payment_id]).any? { |l| l.description == "payment" } }
        ship_full = e.(:shipping_cost) + (sid ? rs.first.dig(:shipping, :buyer_cost).to_f : 0)
        mp_ship = approved.sum { |p| p.shipping_fee.to_f }
        status = sale_status(sale_pays, net, released ? credited : nil, expected, coupon,
                             at_release: net - (ship_full - mp_ship), not_charged: mp_ship.zero? && e.(:shipping_cost).positive? ? net - e.(:shipping_cost) : nil)
        release_at = approved.filter_map(&:money_release_date).max
        fee_billed = rs.sum { |r| Array(bill_order[r[:order_id]]).select { |x| FinanceQuery::GROUPS[:venda].include?(x.detail_sub_type.to_s.sub(/\AB/, "C")) }.sum(&:signed_amount) }
        ship_billed = sid ? Array(bill_ship[sid]).select { |x| FinanceQuery::GROUPS[:envio].include?(x.detail_sub_type.to_s.sub(/\AB/, "C")) }.sum(&:signed_amount) : 0.0
        {
          key: key.to_s, shipment_id: sid, order_ids: rs.map { |r| r[:order_id] }, pack_id: rs.first[:pack_id], date: rs.first[:date_created],
          items: rs.flat_map { |r| Array(r[:items]).map { |i| i[:title] } }.uniq.first(3),
          revenue: e.(:revenue).round(2), expected: expected.round(2),
          lunna_fee: e.(:fee).round(2), lunna_shipping: (e.(:shipping_cost) + (sid ? rs.first.dig(:shipping, :buyer_cost).to_f : 0)).round(2),
          billed_fee: fee_billed.round(2), billed_shipping: ship_billed.round(2), billed: billing.any? && (fee_billed.nonzero? || ship_billed.nonzero?) ? true : false,
          mp_gross: sale_pays.select { |p| p.status == "approved" }.sum { |p| p.transaction_amount.to_f }.round(2),
          mp_fee: approved.sum { |p| p.ml_fee.to_f + p.mp_fee.to_f + p.financing_fee.to_f }.round(2),
          mp_shipping: approved.sum { |p| p.shipping_fee.to_f }.round(2), buyer_paid: buyer_pays.select { |p| p.status == "approved" }.sum { |p| p.transaction_amount.to_f }.round(2),
          mp_coupon: coupon.round(2), mp_other: approved.sum { |p| p.other_charges.to_f }.round(2),
          mp_net: net.round(2), diff: (%w[conferido frete_liberacao].include?(status) ? 0.0 : (released ? credited : net) - expected).round(2), credited: credited.round(2),
          release_date: release_at&.iso8601, payment_ids: pays.map(&:payment_id), payment_statuses: pays.map(&:status).uniq,
          status: status, credit: credit_status(approved, net, credited, expected, release_at, lines_until, now)
        }
      end
      summarize(result)
    end

    # at_release: o líquido se a etiqueta for descontada na liberação (carrinho com frete na fatura do ML);
    # not_charged: o líquido se o frete previsto no Lunna não tivesse sido cobrado.
    def sale_status(sale_pays, net, credited, expected, coupon, at_release:, not_charged:)
      near = ->(v) { v && (v - expected).abs < TOLERANCE }
      return "sem_pagamento" if sale_pays.empty?
      return "mediacao" if sale_pays.any? { |p| p.status == "in_mediation" }
      return "reembolso" if sale_pays.none? { |p| p.status == "approved" }
      return "conferido" if near.(net)
      return "frete_liberacao" if near.(credited) || (credited.nil? && near.(at_release))
      return "cupom" if coupon.positive? && (near.(net + coupon) || near.(credited && credited + coupon))
      return "frete_nao_cobrado" if not_charged && (net - expected - (net - not_charged)).abs < TOLERANCE

      "diferenca"
    end

    def credit_status(approved, net, credited, expected, release_at, lines_until, now)
      return "sem_credito" if approved.empty? || net.abs < TOLERANCE
      return "creditado" if (credited - net).abs < TOLERANCE || (credited.abs >= TOLERANCE && (credited - expected).abs < TOLERANCE)
      return "a_liberar" if release_at.nil? || release_at > now
      return "aguardando_relatorio" if lines_until.nil? || release_at > lines_until

      "nao_localizado"
    end

    def summarize(list)
      sum = ->(rows, k) { rows.sum { |r| r[k].to_f }.round(2) }
      by = ->(field, table) do
        table.keys.map do |k|
          rs = list.select { |r| r[field] == k }
          { key: k, label: table[k][0], tone: table[k][1], count: rs.size, expected: sum.(rs, :expected), mp_net: sum.(rs, :mp_net), diff: sum.(rs, :diff), credited: sum.(rs, :credited) }
        end.reject { |x| x[:count].zero? }
      end
      paid = list.select { |r| %w[conferido frete_liberacao cupom diferenca].include?(r[:status]) }
      billed = paid.select { |r| r[:billed] }
      {
        totals: { sales: list.size, expected: sum.(list, :expected), mp_net: sum.(list, :mp_net), credited: sum.(list, :credited),
                  diff: sum.(paid, :diff), coupon: sum.(list, :mp_coupon),
                  to_release: list.select { |r| %w[a_liberar aguardando_relatorio].include?(r[:credit]) }.sum { |r| r[:mp_net] - r[:credited] }.round(2) },
        by_status: by.(:status, STATUS),
        by_credit: by.(:credit, CREDIT),
        # Tarifa e frete nas três fontes, só nas vendas pagas e já faturadas (o mesmo conjunto nas três colunas)
        legs: [
          { key: "fee", label: "Tarifa de venda", lunna: sum.(billed, :lunna_fee), billed: sum.(billed, :billed_fee), mp: sum.(billed, :mp_fee),
            note: "Lunna: tarifa da venda. Faturado: tarifas de venda do extrato do ML. Mercado Pago: tarifa do ML + processamento + parcelamento sem juros descontados no pagamento." },
          { key: "shipping", label: "Frete (etiqueta cheia)", lunna: sum.(billed, :lunna_shipping), billed: sum.(billed, :billed_shipping), mp: sum.(billed, :mp_shipping),
            note: "Custo do vendedor + parte do comprador. O comprador paga a parte dele num pagamento à parte, creditado na conta (#{money(sum.(billed, :buyer_paid))} aqui)." },
          { key: "coupon", label: "Cupom com participação do vendedor", lunna: 0.0, billed: nil, mp: sum.(billed, :mp_coupon),
            note: "Desconto no pagamento quando o cupom tem participação do vendedor. O Lunna ainda não conta esse custo na venda." },
          { key: "net", label: "Líquido da venda", lunna: sum.(billed, :expected), billed: nil, mp: sum.(billed, :mp_net),
            note: "Receita − tarifa − frete do vendedor (Lunna) x valor líquido do pagamento no Mercado Pago, já com a parte do comprador no frete." }
        ].map { |l| l.merge(diff: (l[:mp].to_f - l[:lunna].to_f).round(2), sales: billed.size) },
        divergent: list.reject { |r| %w[conferido frete_liberacao].include?(r[:status]) && %w[creditado a_liberar aguardando_relatorio sem_credito].include?(r[:credit]) }
                       .sort_by { |r| [ r[:status] == "diferenca" || r[:credit] == "nao_localizado" ? 0 : 1, -r[:diff].abs ] }.first(150)
      }
    end

    # --- movimentos da conta no período (relatório de liberações) ---

    def account_movements
      cur = movements(@from, @to)
      prev = movements(@prev_from, @prev_to)
      keys = (cur[:by].keys + prev[:by].keys).uniq
      rows = keys.map do |k|
        c = cur[:by][k] || { credit: 0.0, debit: 0.0, count: 0 }
        p = prev[:by][k] || { credit: 0.0, debit: 0.0, count: 0 }
        { key: k, label: MpReleaseLine::LABELS[k] || k.to_s.tr("_", " "), credit: c[:credit].round(2), debit: c[:debit].round(2),
          net: (c[:credit] - c[:debit]).round(2), count: c[:count], previous: (p[:credit] - p[:debit]).round(2) }
      end.sort_by { |r| -(r[:credit] + r[:debit]) }
      reserves = @account.mp_release_lines.where("description LIKE 'reserve_for_%'").where(date: ..@to).group(:description).sum("net_credit - net_debit")
                         .reject { |_, v| v.to_f.abs < 0.01 }.map { |k, v| { key: k, label: MpReleaseLine::LABELS[k] || k, amount: v.to_f.round(2) } }
      { opening: cur[:opening], closing: cur[:closing], credits: cur[:credits], debits: cur[:debits], previous_credits: prev[:credits], previous_debits: prev[:debits],
        rows: rows, reserves: reserves,
        note: "Do relatório de liberações do Mercado Pago (gerado toda segunda-feira com a semana anterior). Reservas: valores retidos e devolvidos; o saldo negativo é o que ainda está retido desde #{@account.mp_release_lines.minimum(:date)&.in_time_zone(@zone)&.strftime('%d/%m/%Y') || '—'}." }
    end

    def movements(from, to)
      scope = @account.mp_release_lines.where(record_type: "release", date: from..to)
      by = scope.group(:description).pluck(:description, Arel.sql("SUM(net_credit)"), Arel.sql("SUM(net_debit)"), Arel.sql("COUNT(*)"))
                .to_h { |d, c, db, n| [ d, { credit: c.to_f, debit: db.to_f, count: n } ] }
      before = @account.mp_release_lines.where(record_type: "release").where(date: ...from).order(:date, :id).last
      last = scope.order(:date, :id).last
      { by: by, credits: by.values.sum { |v| v[:credit] }.round(2), debits: by.values.sum { |v| v[:debit] }.round(2),
        opening: before&.balance&.to_f, closing: last&.balance&.to_f }
    end

    def money(v) = ActiveSupport::NumberHelper.number_to_currency(v, unit: "R$", separator: ",", delimiter: ".", format: "%u %n")
  end
end
