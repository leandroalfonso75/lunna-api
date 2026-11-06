# Lançamentos manuais do Financeiro (abas Receita e Despesas). Leitura para todos; incluir/alterar/excluir só admin.
# GET    /api/finance/entries?account_id=&from=&to=&entry_type=
# POST   /api/finance/entries   { entry_type, date, category, description, amount, notes }
# PATCH  /api/finance/entries/:id
# DELETE /api/finance/entries/:id
class FinanceEntriesController < ApplicationController
  include CurrentAccount

  before_action :require_admin!, only: [ :create, :update, :destroy ]

  def index
    scope = Current.account.finance_entries.order(date: :desc, created_at: :desc)
    scope = scope.where(entry_type: params[:entry_type]) if params[:entry_type].present?
    scope = scope.where("date >= ?", params[:from]) if params[:from].present?
    scope = scope.where("date <= ?", params[:to]) if params[:to].present?
    render json: { entries: scope.includes(:user).map { |e| entry_json(e) },
                   categories: { receita: FinanceEntry::INCOME_CATEGORIES, despesa: FinanceEntry::EXPENSE_CATEGORIES } }
  end

  def create
    entry = Current.account.finance_entries.new(entry_params.merge(user: Current.user))
    if entry.save
      render json: entry_json(entry), status: :created
    else
      render_errors(entry.errors.full_messages, status: :unprocessable_content)
    end
  end

  def update
    entry = Current.account.finance_entries.find(params[:id])
    if entry.update(entry_params)
      render json: entry_json(entry)
    else
      render_errors(entry.errors.full_messages, status: :unprocessable_content)
    end
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Lançamento não encontrado." ], status: :not_found)
  end

  def destroy
    Current.account.finance_entries.find(params[:id]).destroy!
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_errors([ "Lançamento não encontrado." ], status: :not_found)
  end

  private

  def entry_params
    params.permit(:entry_type, :date, :category, :description, :amount, :notes)
  end

  def entry_json(e)
    { id: e.id, entry_type: e.entry_type, date: e.date, category: e.category, description: e.description, amount: e.amount.to_f,
      notes: e.notes, user: e.user&.name, created_at: e.created_at }
  end
end
