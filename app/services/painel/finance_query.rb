# Seção Financeiro (pedido do usuário em 05/11/2026): a saúde financeira da operação no Mercado Livre, num
# demonstrativo de resultado (DRE) do período escolhido, sempre comparado com o período imediatamente anterior de
# mesmo tamanho (hoje x ontem, 30 dias x os 30 anteriores, setembro x agosto).
#
# Fontes, todas já no Lunna:
#   - Vendas (Painel::SalesQuery, mesma conta e mesmos filtros da seção Vendas): receita, custo dos produtos, tarifa de
#     venda, frete do vendedor, imposto, despesas operacionais, reembolsos, Ads por venda;
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
    def self.repasses(account, params = {}) = new(account, params).repasses

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
        revenue: revenue_tab(cur, prev),
        expenses: expenses_tab(cur, prev),
        reconciliation: reconciliation(cur),
        coverage: coverage(current[:from], current[:to]),
        months: sales.send(:available_months)
      }
    end

    # Aba Repasses: conciliação com o Mercado Pago, carregada à parte (só quando a aba abre), com os mesmos filtros.
    def repasses
      sales = SalesQuery.new(@account, @params)
      current = sales.period_rows
      prev_from, prev_to = previous_window(current[:from], current[:to], sales)
      active = current[:rows].select { |r| r[:economics] }
      {
        period: { from: current[:from].iso8601, to: current[:to].iso8601, previous_from: prev_from.iso8601, previous_to: prev_to.iso8601,
                  previous_label: previous_label(current[:from], current[:to], prev_from, prev_to) },
        **RepassesQuery.call(@account, active, current[:from], current[:to], prev_from, prev_to, zone: @zone)
      }
    end

    private

    # --- período anterior ---

    # Mês fechado compara com o mês anterior inteiro; mês em andamento (mês atual ou "mês até hoje") compara com os
    # mesmos dias do mês anterior (05/11 → 01 a 05/10; pedido do usuário em 05/11/2026). Os demais: mesmo nº de dias logo antes.
    def previous_window(from, to, sales)
      key = sales.send(:month_key)
      key ||= @zone.today.strftime("%Y-%m") if sales.send(:preset_key) == "mtd"
      if key
        start = Date.strptime(key, "%Y-%m").prev_month
        last = to.to_date < to.to_date.end_of_month ? [ start + (to.to_date.day - 1), start.end_of_month ].min : start.end_of_month
        return [ start.in_time_zone(@zone).beginning_of_day, last.in_time_zone(@zone).end_of_day ]
      end
      days = (to.to_date - from.to_date).to_i + 1
      [ from - days.days, from - 1.second ]
    end

    # Lançamentos manuais (abas Receita e Despesas) no período.
    def manual(from, to)
      rows = @account.finance_entries.where(date: from.to_date..to.to_date).order(:date).to_a
      { income: rows.select { |e| e.entry_type == "receita" }, expenses: rows.select { |e| e.entry_type == "despesa" } }
    end

    def entry_json(e)
      { id: e.id, entry_type: e.entry_type, date: e.date, category: e.category, description: e.description, amount: e.amount.to_f, notes: e.notes }
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
      # base extrato: o ML cobra a etiqueta cheia; a parte paga pelos compradores (que veio no pagamento da venda) sai
      buyer_shipping = active.group_by { |r| r.dig(:shipping, :id) }.sum { |sid, rs| sid ? rs.first.dig(:shipping, :buyer_cost).to_f : 0.0 }
      shipping = @basis == "extrato" ? ml[:envio][:net] - buyer_shipping : s[:shipping_cost]
      ads = @basis == "extrato" ? ml[:ads][:net] : ads_lunna
      # créditos: bonificações do extrato não ligadas às linhas já líquidas (na base Lunna, as de tarifa/frete das vendas
      # do período contam como crédito, porque a linha de tarifa/frete é a cheia)
      credits = @basis == "extrato" ? ml[:outro][:bonus] : ml[:venda][:bonus] + ml[:envio][:bonus] + ml[:ads][:bonus] + ml[:outro][:bonus]
      revenue = s[:revenue].to_f
      gross = revenue - refunds
      cogs = s[:cost].to_f
      gross_profit = gross - cogs
      entries = manual(from, to)
      other_income = entries[:income].sum { |e| e.amount.to_f }
      other_expenses = entries[:expenses].sum { |e| e.amount.to_f }
      # cupom com participação do vendedor: descontado no pagamento do Mercado Pago (não aparece no extrato do ML)
      coupon = s[:coupon_cost].to_f
      operating = gross_profit - fee - shipping - coupon - s[:tax].to_f - s[:fixed_expenses].to_f - returns[:total] - ml[:full][:net] - ml[:outro][:charge] + credits +
                  other_income - other_expenses
      net = operating - ads
      {
        from: from, to: to, orders: s[:orders].to_i, units: s[:units].to_i, cancelled: s[:cancelled].to_i, ticket: s[:ticket],
        revenue: revenue, refunds: refunds, net_revenue: gross, cogs: cogs, gross_profit: gross_profit,
        fee: fee, shipping: shipping, coupon: coupon, coupon_discount: s[:coupon_discount].to_f, coupon_orders: s[:coupon_orders].to_i, tax: s[:tax].to_f, fixed: s[:fixed_expenses].to_f,
        returns: returns, full: ml[:full], other_ml: ml[:outro][:charge], credits: credits, installments: ml[:parcelamento],
        operating: operating, ads: ads, net: net, other_income: other_income, other_expenses: other_expenses, entries: entries, rows: active,
        matched: matched(active, from, to),
        fee_lunna: s[:fee].to_f, shipping_lunna: s[:shipping_cost].to_f, ads_lunna: ads_lunna, ml: ml, buyer_shipping: buyer_shipping,
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
        row.(:coupon, "(−) Cupons (parte do vendedor)", "expense", c[:coupon], p[:coupon],
             note: "#{c[:coupon_orders]} venda(s) com cupom · desconto total #{money(c[:coupon_discount])}, descontado no pagamento do Mercado Pago"),
        row.(:tax, "(−) Impostos (#{@company.tax_pct.to_f}% da receita)", "expense", c[:tax], p[:tax]),
        row.(:fixed, "(−) Despesas Operacionais (#{pct(c[:fixed], c[:revenue])}% da receita)", "expense", c[:fixed], p[:fixed],
             note: "mês fechado com despesas operacionais lançadas (Despesas › Incluir Despesas): total do mês ÷ faturamento do mês; nos demais, o padrão de #{@company.fixed_expenses_pct.to_f}% (Configurações › Empresa)"),
        row.(:returns, "(−) Despesas com devoluções", "expense", c[:returns][:total], p[:returns][:total],
             note: "#{c[:returns][:count]} devolução(ões) com custo de #{c[:returns][:completed]} efetivadas; #{c[:returns][:expired]} expiradas",
             breakdown: c[:returns][:by_kind].map { |k, v| { label: ReturnsQuery::CATEGORY_LABELS[{ "frete_envio" => :envio, "frete_devolucao" => :devolucao, "tarifa_venda" => :venda }[k]] || k.to_s.humanize, amount: v } }),
        row.(:full, "(−) Despesas do Full", "expense", c[:full][:net], p[:full][:net], note: "armazenamento, coleta e estoque antigo, pelo extrato do ML",
             breakdown: c[:full][:lines].map { |k, v| { label: k, amount: v } }),
        row.(:other_ml, "(−) Outras cobranças do Mercado Livre", "expense", c[:other_ml], p[:other_ml], note: "extrato: Minha página, DIFAL e cobranças não classificadas",
             breakdown: c[:ml][:outro][:lines].select { |_, v| v.positive? }.map { |k, v| { label: k, amount: v } }),
        row.(:credits, "(+) Créditos e bonificações do Mercado Livre", "credit", c[:credits], p[:credits], note: "tarifas e fretes devolvidos pelo ML (devoluções, cancelamentos de cobrança)"),
        row.(:other_income, "(+) Outras receitas (lançadas)", "credit", c[:other_income], p[:other_income], note: "lançamentos manuais da aba Receita",
             breakdown: c[:entries][:income].group_by(&:category).map { |k, v| { label: k, amount: v.sum { |e| e.amount.to_f }.round(2) } }),
        row.(:other_expenses, "(−) Outras despesas (lançadas)", "expense", c[:other_expenses], p[:other_expenses], note: "lançamentos manuais da aba Despesas",
             breakdown: c[:entries][:expenses].group_by(&:category).map { |k, v| { label: k, amount: v.sum { |e| e.amount.to_f }.round(2) } }),
        row.(:operating, "= Lucro antes de Ads", "subtotal", c[:operating], p[:operating], note: "margem #{pct(c[:operating], c[:revenue])}%"),
        row.(:ads, "(−) Product Ads", "expense", c[:ads], p[:ads], note: basis_note(:ads, c)),
        row.(:net, "= Lucro pós Ads", "total", c[:net], p[:net], note: "margem líquida #{pct(c[:net], c[:revenue])}%")
      ]
    end

    def basis_note(key, c)
      lunna, extrato = case key
      when :fee then [ c[:fee_lunna], c[:ml][:venda][:net] ]
      when :shipping then [ c[:shipping_lunna], c[:ml][:envio][:net] - c[:buyer_shipping].to_f ]
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
        [ "Custo dos produtos", c[:cogs] ], [ "Tarifas de venda", c[:fee] ], [ "Fretes", c[:shipping] ], [ "Cupons", c[:coupon] ], [ "Impostos", c[:tax] ],
        [ "Despesas Operacionais", c[:fixed] ], [ "Devoluções e reembolsos", c[:returns][:total] + c[:refunds] ], [ "Full", c[:full][:net] ],
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

    # Conciliação pelas MESMAS vendas e envios do período (06/11/2026): o que o Lunna calculou x o que o extrato cobrou
    # para elas, quantas ainda não foram cobradas e quantas têm valor diferente. O total do extrato pela data da
    # cobrança (calendário) vai à parte, porque mistura vendas de outros períodos e canceladas.
    def matched(active, from, to)
      order_ids = active.map { |r| r[:order_id] }
      ship_ids = active.filter_map { |r| r.dig(:shipping, :id) }.uniq
      rows = @account.ml_billing_charges.where(order_id: order_ids).or(@account.ml_billing_charges.where(shipment_id: ship_ids)).to_a
      by_order = rows.group_by(&:order_id)
      by_ship = rows.group_by(&:shipment_id)
      venda = GROUPS[:venda]
      envio = GROUPS[:envio]
      fee = { lunna: 0.0, extrato: 0.0, pending: 0, pending_amount: 0.0, different: 0 }
      active.each do |r|
        l = r[:economics][:fee].to_f
        billed = Array(by_order[r[:order_id]]).select { |x| venda.include?(x.detail_sub_type.to_s.sub(/\AB/, "C")) }
        fee[:lunna] += l
        if billed.empty?
          fee[:pending] += 1
          fee[:pending_amount] += l
        else
          b = billed.sum(&:signed_amount)
          fee[:extrato] += b
          fee[:different] += 1 if (b - l).abs >= 0.02
        end
      end
      # Frete: o ML cobra do vendedor a etiqueta cheia e o comprador paga a parte dele junto com a venda; o custo
      # líquido (previsto) = cobrado − parte do comprador. Compara cobrado x (previsto + parte do comprador).
      ship = { lunna: 0.0, extrato: 0.0, pending: 0, pending_amount: 0.0, different: 0, buyer_paid: 0.0, over: [] }
      active.group_by { |r| r.dig(:shipping, :id) }.each do |sid, rs|
        next unless sid

        est = rs.first.dig(:shipping, :seller_cost).to_f
        buyer = rs.first.dig(:shipping, :buyer_cost).to_f
        billed = Array(by_ship[sid]).select { |x| envio.include?(x.detail_sub_type.to_s.sub(/\AB/, "C")) }
        ship[:lunna] += est + buyer
        if billed.empty?
          ship[:pending] += 1
          ship[:pending_amount] += est + buyer
        else
          b = billed.sum(&:signed_amount)
          ship[:extrato] += b
          ship[:buyer_paid] += buyer
          if (b - est - buyer).abs >= 0.02
            ship[:different] += 1
            ship[:over] << { shipment_id: sid, order_id: rs.first[:order_id], date: rs.first[:date_created], logistic: rs.first.dig(:shipping, :logistic_type),
                             expected: est.round(2), buyer_paid: buyer.round(2), billed: b.round(2), diff: (b - est - buyer).round(2) }
          end
        end
      end
      # Ads: o ML lança a tarifa do dia no dia seguinte; compara o gasto por dia com a cobrança deslocada em um dia
      ads_extrato = @account.ml_billing_charges.where(charged_at: (from + 1.day)..(to + 1.day)).to_a
        .select { |x| %w[PADS BPAD].include?(x.detail_sub_type) }.sum(&:signed_amount)
      { fee: fee, shipping: ship, ads_extrato: ads_extrato }
    end

    def reconciliation(c)
      m = c[:matched]
      item = ->(key, label, lunna, extrato, note, extra = {}) do
        diff = (extrato.to_f - lunna.to_f).round(2)
        { key: key, label: label, lunna: lunna.to_f.round(2), extrato: extrato.to_f.round(2), diff: diff,
          diff_pct: lunna.to_f.abs > 0.005 ? (diff / lunna.to_f * 100).round(1) : nil, note: note, **extra }
      end
      fee = m[:fee]
      ship = m[:shipping]
      [
        item.(:fee, "Tarifas de venda", fee[:lunna] - fee[:pending_amount], fee[:extrato],
              "Mesmas vendas do período. #{fee[:pending]} venda(s) ainda sem cobrança no extrato (#{money(fee[:pending_amount])}) ficam fora; #{fee[:different]} com valor diferente (ajustes do ML, como reembolso parcial da tarifa).",
              { pending: fee[:pending], different: fee[:different], calendar: c[:ml][:venda][:net] }),
        item.(:shipping, "Fretes (previsto + parte do comprador)", ship[:lunna] - ship[:pending_amount], ship[:extrato],
              "Mesmos envios do período. O ML cobra a etiqueta cheia e o comprador paga a parte dele junto com a venda (#{money(ship[:buyer_paid])} neste período); o custo do vendedor é a diferença. #{ship[:pending]} envio(s) ainda sem cobrança ficam fora; #{ship[:different]} cobrado(s) fora dessa conta.",
              { pending: ship[:pending], different: ship[:different], calendar: c[:ml][:envio][:net], buyer_paid: ship[:buyer_paid].round(2), divergent: ship[:over].sort_by { |o| -o[:diff].abs }.first(50) }),
        item.(:ads, "Product Ads", c[:ads_lunna], m[:ads_extrato],
              "Gasto por dia da seção Ads x tarifa de Product Ads do extrato, que o ML lança no dia seguinte (comparação deslocada em um dia).",
              { calendar: c[:ml][:ads][:net] }),
        item.(:returns, "Fretes de devolução", c[:returns][:by_kind]["frete_devolucao"].to_f, c[:ml][:devolucao][:net],
              "Lunna: custo por devolução que o ML informa, pelas reclamações abertas no período. Extrato: tarifas de devolução cobradas no período (a cobrança vem dias depois da abertura).",
              { calendar: c[:ml][:devolucao][:net] })
      ]
    end

    # --- aba Receita: de onde vem a receita, com o período anterior ---

    def revenue_tab(c, p)
      by = ->(rows, &key) { rows.group_by(&key).transform_values { |rs| { revenue: rs.sum { |r| r[:economics][:revenue] }.round(2), orders: rs.map { |r| r[:pack_id] || r[:order_id] }.uniq.size, units: rs.sum { |r| r[:units] } } } }
      logistic = ->(r) { Painel::ClaimContest::LOGISTICS[r.dig(:shipping, :logistic_type)] || r.dig(:shipping, :logistic_type) || "sem envio" }
      cur_log = by.(c[:rows], &logistic)
      prev_log = by.(p[:rows], &logistic)
      cur_items = item_revenue(c[:rows])
      prev_items = item_revenue(p[:rows])
      ads_cur = ads_sales(c[:from], c[:to])
      ads_prev = ads_sales(p[:from], p[:to])
      {
        totals: { revenue: cmp(c[:revenue], p[:revenue]), refunds: cmp(c[:refunds], p[:refunds], invert: true), net_revenue: cmp(c[:net_revenue], p[:net_revenue]),
                  orders: cmp(c[:orders], p[:orders]), units: cmp(c[:units], p[:units]), ticket: cmp(c[:ticket], p[:ticket]),
                  other_income: cmp(c[:other_income], p[:other_income]), cancelled: cmp(c[:cancelled], p[:cancelled], invert: true) },
        by_logistic: (cur_log.keys | prev_log.keys).map { |k| { label: k, **cmp(cur_log.dig(k, :revenue), prev_log.dig(k, :revenue)), orders: cur_log.dig(k, :orders).to_i, units: cur_log.dig(k, :units).to_i, share: pct(cur_log.dig(k, :revenue), c[:revenue]) } }.sort_by { |x| -x[:value] },
        by_product: cur_items.sort_by { |_, v| -v[:revenue] }.first(15).map { |id, v| { item_id: id, title: v[:title], sku: v[:sku], units: v[:units], **cmp(v[:revenue], prev_items.dig(id, :revenue)), share: pct(v[:revenue], c[:revenue]) } },
        ads_vs_organic: { ads: cmp(ads_cur, ads_prev), organic: cmp([ c[:revenue] - ads_cur, 0 ].max, [ p[:revenue] - ads_prev, 0 ].max), ads_share: pct(ads_cur, c[:revenue]) },
        weekly: weekly(c[:daily], p[:daily]),
        entries: c[:entries][:income].map { |e| entry_json(e) }
      }
    end

    def item_revenue(rows)
      rows.each_with_object(Hash.new { |h, k| h[k] = { revenue: 0.0, units: 0, title: nil, sku: nil } }) do |r, memo|
        r[:items].each do |i|
          m = memo[i[:item_id]]
          m[:revenue] += i[:unit_price].to_f * i[:quantity].to_i
          m[:units] += i[:quantity].to_i
          m[:title] ||= i[:title]
          m[:sku] ||= i[:sku]
        end
      end.transform_values { |v| v.merge(revenue: v[:revenue].round(2)) }
    end

    # Vendas atribuídas ao Ads no período (diretas + indiretas), pela seção Ads.
    def ads_sales(from, to) = @account.ml_ad_daily_metrics.where(date: from.to_date..to.to_date).sum(:total_amount).to_f

    # Receita por semana (7 dias corridos a partir do 1º dia do período), atual x anterior pela mesma posição.
    def weekly(cur, prev)
      cur.each_slice(7).with_index.map do |days, i|
        pdays = prev.each_slice(7).to_a[i] || []
        { label: "#{days.first[:date][5..].tr('-', '/')} a #{days.last[:date][5..].tr('-', '/')}", revenue: days.sum { |d| d[:revenue] }.round(2),
          previous_revenue: pdays.empty? ? nil : pdays.sum { |d| d[:revenue] }.round(2), orders: days.sum { |d| d[:orders] } }
      end
    end

    # --- aba Despesas: cada despesa com o período anterior, as do extrato e os lançamentos ---

    def expenses_tab(c, p)
      items = [
        [ :cogs, "Custo dos produtos vendidos", c[:cogs], p[:cogs], "Olist (PEPS) ou custo manual" ],
        [ :fee, "Tarifas de venda do ML", c[:fee], p[:fee], basis_note(:fee, c) ],
        [ :shipping, "Fretes pagos pelo vendedor", c[:shipping], p[:shipping], basis_note(:shipping, c) ],
        [ :coupon, "Cupons (parte do vendedor)", c[:coupon], p[:coupon], "descontado no pagamento do Mercado Pago" ],
        [ :tax, "Impostos", c[:tax], p[:tax], "#{@company.tax_pct.to_f}% da receita" ],
        [ :fixed, "Despesas Operacionais", c[:fixed], p[:fixed], "#{pct(c[:fixed], c[:revenue])}% da receita (lançadas por mês em Incluir Despesas; sem lançamento, padrão de #{@company.fixed_expenses_pct.to_f}%)" ],
        [ :returns, "Devoluções", c[:returns][:total], p[:returns][:total], "card Devoluções em Reclamações" ],
        [ :refunds, "Reembolsos a compradores", c[:refunds], p[:refunds], "reduzem a receita" ],
        [ :full, "Full (armazenamento, coleta, estoque antigo)", c[:full][:net], p[:full][:net], "extrato do ML" ],
        [ :other_ml, "Outras cobranças do ML", c[:other_ml], p[:other_ml], "extrato do ML" ],
        [ :ads, "Product Ads", c[:ads], p[:ads], basis_note(:ads, c) ],
        [ :other_expenses, "Outras despesas (lançadas)", c[:other_expenses], p[:other_expenses], "lançamentos manuais" ]
      ].map { |key, label, cur, prev, note| { key: key, label: label, note: note, share: pct(cur, c[:revenue]), **cmp(cur, prev, invert: true) } }
      total = items.sum { |i| i[:value] }
      {
        items: items.sort_by { |i| -i[:value] }, total: cmp(total, items.sum { |i| i[:previous] }, invert: true), total_share: pct(total, c[:revenue]),
        entries: c[:entries][:expenses].map { |e| entry_json(e) }
      }
    end

    def coverage(from, to)
      first = @account.ml_billing_charges.minimum(:charged_at)
      { billing_from: first, billing_synced_at: @account.billing_synced_at, orders_from: oldest_order,
        billing_covers: first.present? && first <= from, orders_cover: oldest_order <= from }
    end
  end
end
