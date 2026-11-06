# Seção Financeiro: demonstrativo de resultado do período com comparativo do período anterior, indicadores, gráficos,
# extrato do ML e conciliação. Mesmos filtros de Vendas (period|month|from/to, logistic, shipping, q) e basis=lunna|extrato.
# GET /api/finance?account_id=...
class FinanceController < ApplicationController
  include CurrentAccount

  def show
    render json: Painel::FinanceQuery.call(Current.account, params)
  end
end
