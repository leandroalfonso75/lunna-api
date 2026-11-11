# Despesas Operacionais mensais da empresa (Financeiro › Despesas › Incluir Despesas). Leitura para todos; escrita só admin.
# GET    /api/finance/fixed_expenses?month=YYYY-MM   → lançamentos do mês, comparativo Faturamento x Despesas Operacionais e os meses lançados
# POST   /api/finance/fixed_expenses                 { month, category, description, amount }
# PATCH  /api/finance/fixed_expenses/:id
# DELETE /api/finance/fixed_expenses/:id
# POST   /api/finance/fixed_expenses/copy            { month, from } copia os lançamentos de outro mês (padrão: o anterior)
class FixedExpensesController < ApplicationController
  before_action :require_admin!, only: [ :create, :update, :destroy, :copy ]

  def index
    month = parse_month(params[:month]) || Painel::FixedExpenseRate::ZONE.today.beginning_of_month
    rate = Painel::FixedExpenseRate.new(Current.company)
    entries = scope.where(month: month).order(:created_at).includes(:user)
    months = scope.distinct.order(month: :desc).pluck(:month)
    render json: {
      month: month.strftime("%Y-%m"), entries: entries.map { |e| entry_json(e) }, categories: FixedExpense::CATEGORIES,
      summary: summary_json(rate.summary(month)),
      months: months.map { |m| summary_json(rate.summary(m)) }
    }
  end

  def create
    entry = scope.new(entry_params.merge(user: Current.user))
    entry.month = parse_month(params[:month])
    if entry.save
      render json: entry_json(entry), status: :created
    else
      render_errors(entry.errors.full_messages, status: :unprocessable_content)
    end
  end

  def update
    entry = scope.find(params[:id])
    if entry.update(entry_params)
      render json: entry_json(entry)
    else
      render_errors(entry.errors.full_messages, status: :unprocessable_content)
    end
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Despesa não encontrada." ], status: :not_found)
  end

  def destroy
    scope.find(params[:id]).destroy!
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Despesa não encontrada." ], status: :not_found)
  end

  def copy
    month = parse_month(params[:month])
    return render_errors([ "Informe o mês." ], status: :unprocessable_content) unless month

    from = parse_month(params[:from]) || month.prev_month
    source = scope.where(month: from).order(:created_at).to_a
    return render_errors([ "Não há despesas lançadas em #{from.strftime('%m/%Y')} para copiar." ], status: :unprocessable_content) if source.empty?

    FixedExpense.transaction do
      source.each { |e| scope.create!(month: month, category: e.category, description: e.description, amount: e.amount, user: Current.user) }
    end
    render json: { copied: source.size }, status: :created
  end

  private

  def scope = FixedExpense.where(company_id: Current.company.id)

  def entry_params = params.permit(:category, :description, :amount)

  def parse_month(value)
    Date.strptime(value.to_s, "%Y-%m")
  rescue ArgumentError
    nil
  end

  def entry_json(e)
    { id: e.id, month: e.month.strftime("%Y-%m"), category: e.category, description: e.description, amount: e.amount.to_f,
      user: e.user&.name, created_at: e.created_at }
  end

  def summary_json(m)
    m.merge(month: m[:month].strftime("%Y-%m"), pct: m[:pct]&.round(2), applied_pct: m[:applied_pct].to_f.round(2))
  end
end
