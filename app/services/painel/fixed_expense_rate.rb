# Percentual de despesas operacionais que vale para cada mês (regra do usuário em 11/11/2026).
#   - Mês já fechado, com despesas operacionais lançadas (Financeiro › Despesas › Incluir Despesas) e com faturamento:
#     percentual = total das despesas operacionais do mês ÷ faturamento do mês. Vale para todas as vendas daquele mês (Vendas e DRE).
#   - Mês corrente, mês sem lançamento ou sem faturamento: o padrão de Configurações › Empresa (`fixed_expenses_pct`).
# Faturamento do mês = receita das vendas não canceladas de todas as contas da empresa (preço × quantidade, pela data da
# venda no fuso de São Paulo), a mesma receita da seção Vendas.
# Preço de anúncio e promoção (Anúncios, Curva ABC, Promoções) olham para frente e seguem no padrão da empresa.
module Painel
  class FixedExpenseRate
    ZONE = ActiveSupport::TimeZone["America/Sao_Paulo"]

    def initialize(company)
      @company = company
      @months = {}
    end

    def default_pct = @company.fixed_expenses_pct.to_f

    # date: Date, ou Time (convertido para o dia em São Paulo)
    def pct_for(date)
      month(date)[:applied_pct]
    end

    # => { month:, revenue:, total:, pct:, default_pct:, applied_pct:, state: }
    # state: "aplicado" | "mes_corrente" | "sem_lancamentos" | "sem_faturamento"
    def month(date)
      day = date.is_a?(Date) && !date.is_a?(DateTime) ? date : date.in_time_zone(ZONE).to_date
      first = day.beginning_of_month
      @months[first] ||= build(first)
    end

    private

    def build(first)
      total = totals[first].to_f
      revenue = revenue_of(first)
      pct = total.positive? && revenue.positive? ? (total / revenue * 100.0) : nil
      state = if total.zero? then "sem_lancamentos"
      elsif first >= current_month then "mes_corrente"
      elsif revenue.zero? then "sem_faturamento"
      else "aplicado"
      end
      { month: first, revenue: revenue.round(2), total: total.round(2), pct: pct, default_pct: default_pct,
        applied_pct: state == "aplicado" ? pct : default_pct, state: state }
    end

    def current_month = ZONE.today.beginning_of_month

    def totals
      @totals ||= FixedExpense.where(company_id: @company.id).group(:month).sum(:amount)
    end

    # Só consulta o faturamento de mês com lançamento (os demais usam o padrão e não precisam dele).
    def revenue_of(first)
      return 0.0 unless totals[first].to_f.positive? || @always_revenue

      self.class.revenue(@company, first)
    end

    public

    # Comparativo para a tela: sempre traz o faturamento, mesmo sem lançamento.
    def summary(date)
      @always_revenue = true
      first = date.to_date.beginning_of_month
      build(first)
    ensure
      @always_revenue = false
    end

    def self.revenue(company, first)
      from = ZONE.local(first.year, first.month, 1)
      MlOrderItem.joins("JOIN ml_orders o ON o.order_id = ml_order_items.order_id")
        .where(o: { ml_account_id: company.ml_accounts.select(:id) }).where.not(o: { status: %w[cancelled invalid] })
        .where("o.date_created >= ? AND o.date_created < ?", from, from + 1.month)
        .sum("ml_order_items.unit_price * ml_order_items.quantity").to_f
    end
  end
end
