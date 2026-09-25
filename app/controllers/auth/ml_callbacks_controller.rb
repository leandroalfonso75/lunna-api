# GET /auth/ml/callback (público) — puro repasse, sem tocar no banco nem
# chamar o ML. Devolve o `code`/`state` pro front, que loga terminar a
# conexão em POST /api/ml_accounts/connect (autenticado). Isso é o que
# vincula o state ao usuário certo (DECISOES §5) — o navegador sozinho não
# prova nada, só o usuário logado que originalmente gerou o state.
module Auth
  class MlCallbacksController < ApplicationController
    skip_before_action :authenticate!

    def show
      return redirect_with_result("cancelada") if params[:error].present?
      return redirect_with_result("link_invalido") if params[:code].blank? || params[:state].blank?

      redirect_to "#{ENV.fetch("FRONT_URL")}/configuracoes?aba=contas" \
        "&code=#{CGI.escape(params[:code])}&state=#{CGI.escape(params[:state])}",
        allow_other_host: true
    end

    private

    def redirect_with_result(code)
      redirect_to "#{ENV.fetch("FRONT_URL")}/configuracoes?aba=contas&ml=#{code}", allow_other_host: true
    end
  end
end
