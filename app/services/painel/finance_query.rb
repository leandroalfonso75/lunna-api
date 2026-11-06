# Seção Financeiro (pedido do usuário em 05/11/2026): a saúde financeira da operação no Mercado Livre, num
# demonstrativo de resultado (DRE) do período escolhido, sempre comparado com o período imediatamente anterior de
# mesmo tamanho (hoje x ontem, 30 dias x os 30 anteriores, setembro x agosto).
#
# Fontes, todas já no Lunna:
#   - Vendas (Painel::SalesQuery, mesma conta e mesmos filtros da seção Vendas): receita, custo dos produtos, tarifa de
#     venda, frete do vendedor, imposto, despesas fixas, reembolsos, Ads por venda;
#   - Ads (ml_ad_daily_metrics): gasto por dia;
#   - Devoluções (Painel::ReturnsQuery): custos das devoluções do período;
#   - Extrato de faturamento do ML (ml_billing_charges): despesas do Full (armazenamento, coleta, estoque antigo),
#     outras cobranças (Minha página, DIFAL...), e os créditos/bonificações (cancelamento de tarifas e fretes).
#
# Base das linhas "Tarifas do ML", "Fretes" e "Ads": `basis=lunna` (padrão: calculado venda a venda, pela data da
# venda) ou `basis=extrato` (o que o ML cobrou de fato no período, pela data da cobrança). A conciliação mostra as duas
# lado a lado com a diferença.
module Painel
  class FinanceQuery
    GROUPS = {
      venda: %w[CVVML CVVPRC CVVFNU CVVFN], envio: %w[CFFE CXDE CFFI], devolucao: %w[CDSDB CXDED CXDID],
      ads: %w[PADS], parcelamento: %w[CFONPN], full: %w[CFWA CFCBE CFBA]
    }.freeze
    GROUP_LABELS = { venda: "Tarifas de venda", envio: "Fretes", devolucao: "Devoluções", ads: "Product Ads",
                     parcelamento: "Taxa de parcelamento (repassada pelo comprador)", full: "Full", outro: "Outras" }.freeze
    FULL_LABELS = { "CFWA" => "Armazenamento Full", "CFCBE" => "Coleta Full", "CFBA" => "Estoque antigo no Full" }.freeze

    def self.call(account, params = {}) = new(account, params).call

    def initialize(account, params)
      @account = account
      @company = account.company
      @params = params
      @zone = ActiveSupport::TimeZone["America/Sao_Paulo"]
      @basis = params[:basis].to_s == "extrato" ? "extrato" : "lunna"
    end

    def call
      sales = SalesQuery.new(@account, @params)
      current = sales.period_rows
      prev_from, prev_to = previous_window(current[:from], current[:to], sales)
      previous = sales.period_rows(prev_from, prev_to)
      cur = statement(current)
      prev = statement(previous)
      {
        period: { from: current[:from].iso8601, to: current[:to].iso8601, preset: @params[:period].presence || "30d", month: @params[:month].presence,
                  previous_from: prev_from.iso8601, previous_to: prev_to.iso8601, previous_label: previous_label(current[:from], current[:to], prev_from, prev_to),
                  previous_partial: prev_from < oldest_order },
        basis: @basis, filtered: sales.send(:filtered?),
        kpis: kpis(cur, prev),
        statement: lines(cur, prev),
        health: health(cur),
        charts: charts(current, previous, cur),
        statement_ml: statement_ml(current[:from], current[:to]),
        reconciliation: reconciliation(cur),
        coverage: coverage(current[:from], current[:to]),
        months: sales.send(:available_months)
      }
    end

    private

    # --- período anterior ---

    def previous_window(from, to, sales)
      if (key = sales.send(:month_key))
        start = Date.strptime(key, "%Y-%m").prev_month
        return [ start.in_time_zone(@zone).beginning_of_day, start.end_of_month.in_time_zone(@zone).end_of_day ]
      end
      days = (to.to_date - from.to_date).to_i + 1
      [ from - days.days, from - 1.second ]
    end

    def previous_label(from, to, pfrom, pto)
      fmt = ->(t) { t.in_time_zone(@zone).strftime("%d/%m") }
      return "ontem" if from.to_date == @zone.today && to.to_date == @zone.today
      return "anteontem" if from.to_date == @zone.today - 1 && to.to_date == @zone.today - 1

      "#{fmt.(pfrom)} a #{fmt.(pto)}"
    end

    def oldest_order
      @oldest_order ||= @account.ml_orders.minimum(:date_created) || Time.current
    end

    # --- demonstrativo de um período ---

    def statement(period)
      rows = period[:rows]
      active = rows.select { |r| r[:economics] }
      known = active.select { |r| r[:economics][:net_profit] }
      s = period[:summary]
      from, to = period[:from], period[:to]
      refunds = refunds_for(active)
      returns = returns_costs(from, to)
      ml = ml_groups(from, to, active)
      ads_lunna = ads_cost(from, to)
      fee = @basis == "extrato" ? ml[:venda][:net] : s[:fee]
      shipping = @basis == "extrato" ? ml[:envio][:net] : s[:shipping_cost]
      ads = @basis == "extrato" ? ml[:ads][:net] : ads_lunna
      # créditos: bonificações do extrato não ligadas às linhas já líquidas (na base Lunna, as de tarifa/frete das vendas
      # do período contam como crédito, porque a linha de tarifa/frete é a cheia)
      credits = @basis == "extrato" ? ml[:outro][:bonus] : ml[:venda][:bonus] + ml[:envio][:bonus] + ml[:ads][:bonus] + ml[:outro][:bonus]
      revenue = s[:revenue].to_f
      gross = revenue - refunds
      cogs = s[:cost].to_f
      gross_profit = gross - cogs
      operating = gross_profit - fee - shipping - s[:tax].to_f - s[:fixed_expenses].to_f - returns[:total] - ml[:full][:net] - ml[:outro][:charge] + credits
      net = operating - ads
      {
        from: from, to: to, orders: s[:orders].to_i, units: s[:units].to_i, cancelled: s[:cancelled].to_i, ticket: s[:ticket],
        revenue: revenue, refunds: refunds, net_revenue: gross, cogs: cogs, gross_profit: gross_profit,
        fee: fee, shipping: shipping, tax: s[:tax].to_f, fixed: s[:fixed_expenses].to_f,
        returns: returns, full: ml[:full], other_ml: ml[:outro][:charge], credits: credits, installments: ml[:parcelamento],
        operating: operating, ads: ads, net: net,
        fee_lunna: s[:fee].to_f, shipping_lunna: s[:shipping_cost].to_f, ads_lunna: ads_lunna, ml: ml,
        orders_without_cost: s[:orders_without_cost].to_i, known_revenue: known.sum { |r| r[:economics][:revenue] },
        daily: period[:daily]
      }
    end

    # Reembolsos a compradores nas vendas que contam na receita (cancelada já ficou fora).
    def refunds_for(active)
      ids = active.map { |r| r[:order_id] }
      return 0.0 if ids.empty?

      @account.ml_orders.where(order_id: ids).pluck(Arel.sql("payload->'payments'")).sum do |payments|
        Array(payments).sum { |p| p["transaction_amount_refunded"].to_f }
      end
    end

    def returns_costs(from, to)
      data = ReturnsQuery.call(@account, from: from.to_date.iso8601, to: to.to_date.iso8601)
      rows = data[:tabs]["com_custos"]
      { total: rows.sum { |r| r[:costs][:total] }.round(2), count: rows.size,
        by_kind: rows.flat_map { |r| r[:costs][:items] }.group_by { |i| i[:key] }.transform_values { |v| v.sum { |i| i[:amount] }.round(2) },
        completed: data[:summary][:counts]["sem_custo"] + data[:summary][:counts]["com_custos"], expired: data[:summary][:counts]["expiradas"] }
    end

    def ads_cost(from, to)
      @account.ml_ad_daily_metrics.where(date: from.to_date..to.to_date).sum(:cost).to_f
    end

    # Extrato por grupo no período (pela data da cobrança): cobranças, bonificações e líquido.
    def ml_groups(from, to, active)
      rows = @account.ml_billing_charges.where(charged_at: from..to).to_a
      order_ids = active.map { |r| r[:order_id] }.to_set
      groups = Hash.new { |h, k| h[k] = { charge: 0.0, bonus: 0.0, net: 0.0, lines: Hash.new(0.0) } }
      rows.each do |r|
        g = group_of(r.detail_sub_type)
        # bonificação de tarifa/frete de venda cancelada: a venda já está fora da receita, não é crédito a somar (nas duas bases)
        next if r.detail_type != "CHARGE" && %i[venda envio].include?(g) && r.order_id && !order_ids.include?(r.order_id)

        entry = groups[g]
        if r.detail_type == "CHARGE" then entry[:charge] += r.amount.to_f else entry[:bonus] += r.amount.to_f end
        entry[:lines][FULL_LABELS[r.detail_sub_type] || r.transaction_detail.to_s] += r.signed_amount
      end
      (GROUPS.keys + [ :outro ]).each { |g| groups[g][:net] = (groups[g][:charge] - groups[g][:bonus]).round(2); groups[g][:lines] = groups[g][:lines].transform_values { |v| v.round(2) } }
      groups
    end

    # Bonificação usa o código da cobrança trocando o C inicial por B (CVVML → BVVML); Ads é a exceção (PADS → BPAD).
    def group_of(sub)
      return :ads if sub.to_s == "BPAD"

      code = sub.to_s.sub(/\AB/, "C")
      GROUPS.find { |_, codes| codes.include?(code) }&.first || :outro
    end

    # --- saída ---

    def pct(v, base) = base.to_f.abs > 0.005 ? (v.to_f / base.to_f * 100).round(1) : nil

    def cmp(cur, prev, invert: false)
      delta = cur.to_f - prev.to_f
      { value: cur.to_f.round(2), previous: prev.to_f.round(2), delta: delta.round(2),
        delta_pct: prev.to_f.abs > 0.005 ? (delta / prev.to_f.abs * 100).round(1) : nil,
        good: delta.zero? ? nil : (invert ? delta.negative? : delta.positive?) }
    end

    def kpis(c, p)
      {
        revenue: cmp(c[:revenue], p[:revenue]), net: cmp(c[:net], p[:net]), operating: cmp(c[:operating], p[:operating]),
        net_margin: cmp(pct(c[:net], c[:revenue]), pct(p[:net], p[:revenue])),
        gross_margin: cmp(pct(c[:gross_profit], c[:net_revenue]), pct(p[:gross_profit], p[:net_revenue])),
        orders: cmp(c[:orders], p[:orders]), ticket: cmp(c[:ticket], p[:ticket]),
        tacos: cmp(pct(c[:ads], c[:revenue]), pct(p[:ads], p[:revenue]), invert: true),
        ml_cost_pct: cmp(pct(c[:fee] + c[:shipping] + c[:full][:net] + c[:other_ml], c[:revenue]), pct(p[:fee] + p[:shipping] + p[:full][:net] + p[:other_ml], p[:revenue]), invert: true),
        returns_pct: cmp(pct(c[:returns][:total] + c[:refunds], c[:revenue]), pct(p[:returns][:total] + p[:refunds], p[:revenue]), invert: true),
        refunds: cmp(c[:refunds], p[:refunds], invert: true)
      }
    end

    # Linhas do DRE, na ordem de leitura, com % da receita bruta e comparação.
    def lines(c, p)
      row = ->(key, label, kind, cur, prev, **extra) do
        { key: key, label: label, kind: kind, pct_revenue: pct(cur, c[:revenue]), **cmp(cur, prev, invert: kind == "expense"), **extra }
      end
      [
        row.(:revenue, "Receita bruta de vendas", "revenue", c[:revenue], p[:revenue], note: "#{c[:orders]} vendas · #{c[:units]} unidades · ticket #{money(c[:ticket])}"),
        row.(:refunds, "(−) Reembolsos a compradores", "expense", c[:refunds], p[:refunds], note: "dinheiro devolvido em vendas do período (devoluções e acordos)"),
        row.(:net_revenue, "= Receita líquida", "subtotal", c[:net_revenue], p[:net_revenue]),
        row.(:cogs, "(−) Custo dos produtos vendidos", "expense", c[:cogs], p[:cogs], note: c[:orders_without_cost].positive? ? "#{c[:orders_without_cost]} venda(s) sem custo cadastrado ficam de fora" : "custo do Olist (PEPS) ou manual"),
        row.(:gross_profit, "= Lucro bruto", "subtotal", c[:gross_profit], p[:gross_profit], note: "margem bruta #{pct(c[:gross_profit], c[:net_revenue])}%"),
        row.(:fee, "(−) Tarifas de venda do Mercado Livre", "expense", c[:fee], p[:fee], note: basis_note(:fee, c)),
        row.(:shipping, "(−) Fretes pagos pelo vendedor", "expense", c[:shipping], p[:shipping], note: basis_note(:shipping, c)),
        row.(:tax, "(−) Impostos (#{@company.tax_pct.to_f}% da receita)", "expense", c[:tax], p[:tax]),
        row.(:fixed, "(−) Despesas fixas (#{@company.fixed_expenses_pct.to_f}% da receita)", "expense", c[:fixed], p[:fixed]),
        row.(:returns, "(−) Despesas com devoluções", "expense", c[:returns][:total], p[:returns][:total],
             note: "#{c[:returns][:count]} devolução(ões) com custo de #{c[:returns][:completed]} efetivadas; #{c[:returns][:expired]} expiradas",
             breakdown: c[:returns][:by_kind].map { |k, v| { label: ReturnsQuery::CATEGORY_LABELS[{ "frete_envio" => :envio, "frete_devolucao" => :devolucao, "tarifa_venda" => :venda }[k]] || k.to_s.humanize, amount: v } }),
        row.(:full, "(−) Despesas do Full", "expense", c[:full][:net], p[:full][:net], note: "armazenamento, coleta e estoque antigo, pelo extrato do ML",
             breakdown: c[:full][:lines].map { |k, v| { label: k, amount: v } }),
        row.(:other_ml, "(−) Outras cobranças do Mercado Livre", "expense", c[:other_ml], p[:other_ml], note: "extrato: Minha página, DIFAL e cobranças não classificadas",
             breakdown: c[:ml][:outro][:lines].select { |_, v| v.positive? }.map { |k, v| { label: k, amount: v } }),
        row.(:credits, "(+) Créditos e bonificações do Mercado Livre", "credit", c[:credits], p[:credits], note: "tarifas e fretes devolvidos pelo ML (devoluções, cancelamentos de cobrança)"),
        row.(:operating, "= Lucro antes de Ads", "subtotal", c[:operating], p[:operating], note: "margem #{pct(c[:operating], c[:revenue])}%"),
        row.(:ads, "(−) Product Ads", "expense", c[:ads], p[:ads], note: basis_note(:ads, c)),
        row.(:net, "= Lucro líquido pós Ads", "total", c[:net], p[:net], note: "margem líquida #{pct(c[:net], c[:revenue])}%")
      ]
    end

    def basis_note(key, c)
      lunna, extrato = case key
      when :fee then [ c[:fee_lunna], c[:ml][:venda][:net] ]
      when :shipping then [ c[:shipping_lunna], c[:ml][:envio][:net] ]
      else [ c[:ads_lunna], c[:ml][:ads][:net] ]
      end
      @basis == "extrato" ? "cobrado no extrato do ML (por venda: #{money(lunna)})" : "por venda, pela data da venda (extrato do ML: #{money(extrato)})"
    end

    def money(v) = v.nil? ? "—" : ActiveSupport::NumberHelper.number_to_currency(v, unit: "R$", separator: ",", delimiter: ".", format: "%u %n")

    # Sinais simples de saúde, com a meta que a empresa já tem (margem mínima) e referências usuais.
    def health(c)
      margin = pct(c[:net], c[:revenue])
      tacos = pct(c[:ads], c[:revenue])
      ml_pct = pct(c[:fee] + c[:shipping] + c[:full][:net] + c[:other_ml], c[:revenue])
      ret_pct = pct(c[:returns][:total] + c[:refunds], c[:revenue])
      min = @company.min_margin_pct.to_f
      [
        { key: "margin", label: "Margem líquida pós Ads", value: margin, unit: "%", target: "mínima da empresa: #{min}%",
          tone: margin.nil? ? "neutral" : margin >= min ? "ok" : margin >= min / 2 ? "warn" : "bad" },
        { key: "tacos", label: "TACOS (Ads ÷ receita)", value: tacos, unit: "%", target: "referência: até 10%",
          tone: tacos.nil? ? "neutral" : tacos <= 10 ? "ok" : tacos <= 15 ? "warn" : "bad" },
        { key: "ml_cost", label: "Custo do Mercado Livre ÷ receita", value: ml_pct, unit: "%", target: "tarifas, fretes, Full e outras",
          tone: ml_pct.nil? ? "neutral" : ml_pct <= 30 ? "ok" : ml_pct <= 40 ? "warn" : "bad" },
        { key: "returns", label: "Devoluções e reembolsos ÷ receita", value: ret_pct, unit: "%", target: "referência: até 5%",
          tone: ret_pct.nil? ? "neutral" : ret_pct <= 5 ? "ok" : ret_pct <= 10 ? "warn" : "bad" }
      ]
    end

    # Séries para os gráficos: por dia (atual x anterior, alinhados pela posição), composição das despesas e extrato por grupo.
    def charts(current, previous, c)
      cur_days = current[:daily]
      prev_days = previous[:daily]
      ads_cur = ads_by_day(current[:from], current[:to])
      ads_prev = ads_by_day(previous[:from], previous[:to])
      daily = cur_days.each_with_index.map do |d, i|
        pd = prev_days[i]
        { date: d[:date], previous_date: pd&.dig(:date), revenue: d[:revenue].round(2), previous_revenue: pd ? pd[:revenue].round(2) : nil,
          profit: (d[:net_profit] - ads_cur[d[:date]].to_f).round(2), previous_profit: pd ? (pd[:net_profit] - ads_prev[pd[:date]].to_f).round(2) : nil,
          orders: d[:orders], previous_orders: pd&.dig(:orders) }
      end
      expenses = [
        [ "Custo dos produtos", c[:cogs] ], [ "Tarifas de venda", c[:fee] ], [ "Fretes", c[:shipping] ], [ "Impostos", c[:tax] ],
        [ "Despesas fixas", c[:fixed] ], [ "Devoluções e reembolsos", c[:returns][:total] + c[:refunds] ], [ "Full", c[:full][:net] ],
        [ "Outras do ML", c[:other_ml] ], [ "Product Ads", c[:ads] ]
      ].map { |label, v| { label: label, amount: v.to_f.round(2), pct: pct(v, c[:revenue]) } }.reject { |e| e[:amount].abs < 0.005 }
      { daily: daily, expenses: expenses }
    end

    def ads_by_day(from, to)
      @account.ml_ad_daily_metrics.where(date: from.to_date..to.to_date).group(:date).sum(:cost).transform_keys(&:iso8601).transform_values(&:to_f)
    end

    # Extrato do ML no período, por grupo: cobranças, bonificações e líquido, e as linhas de cada grupo.
    def statement_ml(from, to)
      rows = @account.ml_billing_charges.where(charged_at: from..to).to_a
      (GROUPS.keys + [ :outro ]).map do |g|
        list = rows.select { |r| group_of(r.detail_sub_type) == g }
        charge = list.select { |r| r.detail_type == "CHARGE" }.sum { |r| r.amount.to_f }
        bonus = list.reject { |r| r.detail_type == "CHARGE" }.sum { |r| r.amount.to_f }
        { group: g, label: GROUP_LABELS[g], charge: charge.round(2), bonus: bonus.round(2), net: (charge - bonus).round(2), count: list.size,
          neutral: g == :parcelamento,
          lines: list.group_by { |r| r.transaction_detail }.map { |label, rs| { label: label, amount: rs.sum(&:signed_amount).round(2), count: rs.size } }.sort_by { |l| -l[:amount].abs } }
      end.reject { |g| g[:count].zero? }
    end

    # Conciliação Lunna (por venda, pela data da venda) x extrato do ML (pela data da cobrança), no período.
    def reconciliation(c)
      item = ->(key, label, lunna, extrato, note) do
        diff = (extrato.to_f - lunna.to_f).round(2)
        { key: key, label: label, lunna: lunna.to_f.round(2), extrato: extrato.to_f.round(2), diff: diff,
          diff_pct: lunna.to_f.abs > 0.005 ? (diff / lunna.to_f * 100).round(1) : nil, note: note }
      end
      [
        item.(:fee, "Tarifas de venda", c[:fee_lunna], c[:ml][:venda][:net], "Lunna: tarifa de cada venda do período. Extrato: custo por vender/cobrar, taxa de recebimento, menos cancelamentos."),
        item.(:shipping, "Fretes", c[:shipping_lunna], c[:ml][:envio][:net], "Lunna: frete do vendedor de cada venda. Extrato: tarifas de envio menos cancelamentos."),
        item.(:ads, "Product Ads", c[:ads_lunna], c[:ml][:ads][:net], "Lunna: gasto por dia da seção Ads. Extrato: tarifa de Product Ads (costuma ser cobrada no dia seguinte)."),
        item.(:returns, "Fretes de devolução", c[:returns][:by_kind]["frete_devolucao"].to_f, c[:ml][:devolucao][:net], "Lunna: custo por devolução informado pelo ML. Extrato: tarifas de devolução cobradas.")
      ]
    end

    def coverage(from, to)
      first = @account.ml_billing_charges.minimum(:charged_at)
      { billing_from: first, billing_synced_at: @account.billing_synced_at, orders_from: oldest_order,
        billing_covers: first.present? && first <= from, orders_cover: oldest_order <= from }
    end
  end
end
