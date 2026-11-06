# Card Devoluções da seção Reclamações (pedido do usuário em 05/11/2026): as devoluções liberadas pelo ML, em quatro guias.
#   expiradas     — liberadas e não efetivadas: o comprador perdeu o prazo de postagem ou desistiu (devolução expirada,
#                   cancelada, falhou, não entregue, ou autorizada sem devolução gerada e reclamação encerrada);
#   sem_custo     — devolvidas (produto chegou de volta) sem nenhum custo para o vendedor;
#   com_custos    — devolvidas com custo, itemizado: frete de envio retido, frete de devolução, tarifa de venda não
#                   devolvida, reembolso parcial dado ao comprador e outras cobranças do ML ligadas à venda;
#   em_andamento  — etiqueta gerada / a caminho (ainda sem resultado).
# Fontes dos custos:
#   - frete de devolução: `ml_claims.return_cost` (o ML decide por reclamação; 0 = grátis) ou, quando o extrato já
#     trouxe a cobrança do envio de retorno, o valor cobrado de fato;
#   - frete de envio e tarifa de venda: extrato de faturamento (`ml_billing_charges`): cobrança − bonificação da mesma
#     venda/envio. O ML "reintegra a comissão de venda e o custo de envio" quando a venda não se concretiza; o que
#     não foi reintegrado é custo. Sem linhas do extrato para a venda, o frete de envio fica "sem dados";
#   - outras cobranças ligadas à venda/envio no extrato depois da abertura da reclamação.
module Painel
  class ReturnsQuery
    TABS = %w[expiradas sem_custo com_custos em_andamento].freeze
    FINISHED = %w[delivered].freeze
    EXPIRED = %w[expired cancelled failed not_delivered].freeze
    # Categoria de uma linha do extrato pelo código do ML (C = cobrança, B = bonificação/cancelamento do mesmo código):
    #   devolução: DSDB "Tarifa de devolução", XDED/XDID "Tarifa de devolução por envio externo/interno";
    #   envio: FFE/XDE "Tarifa de envio extra ou intermunicipal", FFI "Tarifa por envio interno ao município";
    #   venda: VVML "Custo por vender no ML", VVPRC "Custo por cobrar no MP", VVFNU "Taxa de recebimento",
    #          VVFN/FONPN "Taxa de parcelamento".
    # O texto entra como reserva para códigos novos.
    CATEGORY_RULES = [
      [ :devolucao, /\A[CB](DSDB|XDED|XDID)\z|devolu/i ],
      [ :envio, /\A[CB](FFE|XDE|FFI)\z|tarifa de envio|envio interno/i ],
      [ :venda, /\A[CB](VVML|VVPRC|VVFNU|VVFN|FONPN)\z|custo por vender|custo por cobrar|taxa de recebimento|parcelamento/i ]
    ].freeze
    CATEGORY_LABELS = { envio: "Frete de envio retido", devolucao: "Frete de devolução", venda: "Tarifas da venda não devolvidas",
                        outro: "Outra cobrança" }.freeze

    def self.call(account, params = {}) = new(account, params).call

    def initialize(account, params)
      @account = account
      @params = params
    end

    def call
      claims = scope.to_a
      orders = ClaimsQuery.new(@account, {}).send(:orders_for, claims)
      extra = @account.ml_orders.where(order_id: orders.values.compact.map { |o| o[:order_id] })
        .pluck(:order_id, :shipping_id, :shipment).to_h { |id, ship, s| [ id, { shipping_id: ship, shipment: s || {} } ] }
      charges = charges_for(orders.values.compact.map { |o| o[:order_id] }, extra, claims)
      rows = claims.map { |c| row(c, orders[c.claim_id], extra, charges) }
      tabs = rows.group_by { |r| r[:tab] }
      {
        tabs: TABS.to_h { |t| [ t, (tabs[t] || []).sort_by { |r| -(r[:closed_at] || r[:opened_at]).to_i } ] },
        summary: summary(rows),
        billing: { synced_at: @account.billing_synced_at, periods: @account.ml_billing_charges.distinct.pluck(:period_key).sort },
        period: period_payload
      }
    end

    private

    # Devoluções liberadas: com devolução gerada, ou autorizada pelo ML (ação allow_return/generate_return) sem gerar.
    def scope
      s = @account.ml_claims.where.not(details_synced_at: nil)
      s = s.where("devolution IS NOT NULL OR actions_history::text ~ ?", "(allow_return|generate_return)")
      from, to = period_range
      s = s.where("date_created >= ?", from) if from
      s = s.where("date_created < ?", to) if to
      s.order(date_created: :desc)
    end

    def period_range
      zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
      today = zone.today
      if (m = @params[:month].to_s[/\A\d{4}-\d{2}\z/])
        first = Date.parse("#{m}-01")
        return [ zone.local(first.year, first.month, 1), zone.local(first.year, first.month, 1) + 1.month ]
      end
      if @params[:from].present? || @params[:to].present?
        from = @params[:from].present? ? zone.parse(@params[:from].to_s) : nil
        to = @params[:to].present? ? zone.parse(@params[:to].to_s) + 1.day : nil
        return [ from, to ]
      end
      days = ClaimsQuery::PRESETS[@params[:period].to_s]
      return [ nil, nil ] unless days

      case @params[:period].to_s
      when "today" then [ zone.local(today.year, today.month, today.day), nil ]
      when "yesterday" then [ zone.local(today.year, today.month, today.day) - 1.day, zone.local(today.year, today.month, today.day) ]
      else [ zone.local(today.year, today.month, today.day) - (days - 1).days, nil ]
      end
    end

    def period_payload
      { preset: @params[:period].presence || "all", month: @params[:month].presence, from: @params[:from].presence, to: @params[:to].presence }
    end

    # Linhas do extrato ligadas às vendas (pelo pedido ou pelo envio de ida) e aos envios de devolução.
    def charges_for(order_ids, extra, claims)
      ship_ids = extra.values.filter_map { |e| e[:shipping_id] }
      return_ids = claims.flat_map { |c| Array(c.devolution&.dig("shipments")).filter_map { |s| s["shipment_id"] } }
      rows = @account.ml_billing_charges.where(order_id: order_ids)
        .or(@account.ml_billing_charges.where(shipment_id: ship_ids + return_ids)).to_a
      { by_order: rows.group_by(&:order_id), by_shipment: rows.group_by(&:shipment_id) }
    end

    def row(c, order, extra, charges)
      dev = c.devolution || {}
      status = dev["status"].to_s
      key, label, tone = ClaimsQuery::RETURN_STATES.fetch(status, [ status, status.tr("_", " ").capitalize, "neutral" ])
      shipment = Array(dev["shipments"]).find { |s| s["type"] == "return" } || Array(dev["shipments"]).first || {}
      oinfo = order && extra[order[:order_id]] || {}
      logistic = oinfo.dig(:shipment, "logistic_type")
      refund = ClaimsQuery.new(@account, {}).send(:refund_info, c, order)
      costs = costs_for(c, order, oinfo, shipment, charges)
      tab = tab_for(c, dev, status, costs)
      {
        claim_id: c.claim_id, order_id: order&.dig(:order_id), opened_at: c.date_created, claim_status: c.status,
        closed_at: dev["date_closed"] || dev["last_updated"],
        status: { key: dev.present? ? key : "nao_devolvida", label: dev.present? ? label : "Não devolvida", tone: dev.present? ? tone : "bad", raw: status.presence },
        reason: Painel::ClaimContest::REASON_LABELS[c.reason_name.to_s] || c.reason_detail.presence || c.reason_name || c.reason_id,
        reason_code: c.reason_name,
        buyer: order && (order[:buyer_name].presence || order[:buyer_nickname]),
        item: order&.dig(:item), order_total: order&.dig(:total), logistic: Painel::ClaimContest::LOGISTICS[logistic] || logistic,
        refund: refund, tracking: shipment["tracking_number"], money: dev["status_money"],
        affects_reputation: c.affects_reputation, coverage: c.resolution&.dig("applied_coverage"),
        costs: costs, tab: tab,
        link: order ? "https://www.mercadolivre.com.br/vendas/#{order[:order_id]}/detalhe" : nil
      }
    end

    def tab_for(c, dev, status, costs)
      return "expiradas" if dev.blank? && c.status == "closed"
      return "em_andamento" if dev.blank?
      return "expiradas" if EXPIRED.include?(status)
      return "em_andamento" unless FINISHED.include?(status)

      costs[:total].to_f > 0.005 ? "com_custos" : "sem_custo"
    end

    # Custos da devolução, itemizados. Extrato: cobrança (CHARGE) − bonificação, por categoria, da venda e dos envios.
    def costs_for(c, order, oinfo, return_shipment, charges)
      items = []
      notes = []
      order_rows = order ? Array(charges[:by_order][order[:order_id]]) : []
      out_rows = oinfo[:shipping_id] ? Array(charges[:by_shipment][oinfo[:shipping_id]]) : []
      ret_rows = return_shipment["shipment_id"] ? Array(charges[:by_shipment][return_shipment["shipment_id"]]) : []
      sale_rows = (order_rows + out_rows).uniq(&:detail_id)

      by_cat = sale_rows.group_by { |r| category(r) }
      # frete de envio: só é custo se a venda foi desfeita (dinheiro devolvido) e o ML não reintegrou o frete
      refunded = c.devolution&.dig("status_money") == "refunded" || %w[integral parcial].include?(ClaimsQuery.new(@account, {}).send(:refund_info, c, order)[:key])
      envio = net(by_cat[:envio])
      outbound_known = by_cat[:envio].present? || sale_rows.any?
      if refunded && envio > 0.005
        items << { key: "frete_envio", label: CATEGORY_LABELS[:envio], amount: envio.round(2),
                   detail: "o ML cobrou o frete da venda e não reintegrou depois da devolução" }
      end
      notes << "frete de envio: sem linhas no extrato para esta venda" unless outbound_known

      venda = net(by_cat[:venda])
      if refunded && venda > 0.005
        items << { key: "tarifa_venda", label: CATEGORY_LABELS[:venda], amount: venda.round(2), detail: "tarifa de venda cobrada e não reintegrada" }
      end

      # frete de devolução: cobrança real do extrato (envio de retorno) ou a decisão do ML por reclamação
      ret_billed = net(ret_rows + Array(by_cat[:devolucao]))
      if ret_billed > 0.005
        items << { key: "frete_devolucao", label: CATEGORY_LABELS[:devolucao], amount: ret_billed.round(2), detail: "cobrado no extrato" }
      elsif c.return_cost.to_f > 0.005 && !FINISHED_WITHOUT_RETURN.include?(c.devolution&.dig("status").to_s)
        items << { key: "frete_devolucao", label: CATEGORY_LABELS[:devolucao], amount: c.return_cost.to_f.round(2),
                   detail: "valor que o ML informa cobrar do vendedor por esta devolução" }
      end
      notes << "frete de devolução: ainda não consultado no ML" if c.return_cost_at.nil?

      # reembolso parcial oferecido pelo vendedor e aceito
      partial = Array(c.expected_resolutions).find { |e| e["player_role"] == "respondent" && e["expected_resolution"] == "partial_refund" && e["status"] == "accepted" }
      if partial
        amount = Array(partial["details"]).find { |d| d["key"] == "seller_amount" }&.dig("value").to_f
        items << { key: "reembolso_parcial", label: "Reembolso parcial dado ao comprador", amount: amount.round(2), detail: "aceito pelo comprador" } if amount.positive?
      end

      # outras cobranças do extrato ligadas à venda depois da abertura da reclamação
      Array(by_cat[:outro]).select { |r| r.detail_type == "CHARGE" && r.charged_at && r.charged_at >= c.date_created }.each do |r|
        items << { key: "outro", label: r.transaction_detail.presence || CATEGORY_LABELS[:outro], amount: r.amount.to_f.round(2), detail: "extrato de #{r.period_key[0, 7]}" }
      end

      lines = (sale_rows + ret_rows).uniq(&:detail_id).sort_by { |r| r.charged_at || Time.at(0) }.map do |r|
        { date: r.charged_at, label: r.transaction_detail, kind: r.detail_type, category: category(r), amount: r.signed_amount.round(2), period: r.period_key }
      end
      { items: items, total: items.sum { |i| i[:amount] }.round(2), notes: notes, statement: lines }
    end

    FINISHED_WITHOUT_RETURN = EXPIRED

    def net(rows) = Array(rows).sum(&:signed_amount)

    def category(r)
      CATEGORY_RULES.find { |_, re| r.detail_sub_type.to_s.match?(re) || r.transaction_detail.to_s.match?(re) }&.first || :outro
    end

    def summary(rows)
      by_tab = rows.group_by { |r| r[:tab] }
      costly = by_tab["com_custos"] || []
      items = costly.flat_map { |r| r[:costs][:items] }
      {
        counts: TABS.to_h { |t| [ t, (by_tab[t] || []).size ] },
        total_cost: costly.sum { |r| r[:costs][:total] }.round(2),
        by_kind: items.group_by { |i| i[:key] }.transform_values { |v| v.sum { |i| i[:amount] }.round(2) },
        by_reason: costly.group_by { |r| r[:reason] }.map { |reason, rs| { reason: reason, count: rs.size, cost: rs.sum { |r| r[:costs][:total] }.round(2) } }
          .sort_by { |x| -x[:cost] }.first(8),
        refunded_total: (by_tab["sem_custo"].to_a + costly).sum { |r| r[:refund][:amount].to_f }.round(2),
        no_billing: rows.count { |r| r[:costs][:notes].any? { |n| n.start_with?("frete de envio") } }
      }
    end
  end
end
