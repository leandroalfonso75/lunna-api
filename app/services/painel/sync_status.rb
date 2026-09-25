# Selo de status da sincronização (SPEC 7.1), a partir de ml_sync_runs e do
# status da conta. `minutes_ago` sempre conta a partir da última rodada com
# ok=true (a que o selo mostra "Sincronizado às HH:MM").
module Painel
  class SyncStatus
    OK_WINDOW = 20.minutes

    def self.call(account) = new(account).call

    def initialize(account)
      @account = account
      @last_ok = account.ml_sync_runs.where(ok: true).order(started_at: :desc).first
      @last_finished = account.ml_sync_runs.where.not(finished_at: nil).order(started_at: :desc).first
    end

    def call
      return bad("Reautorização necessária", @account.last_error) if @account.status == "reauth_required"
      return bad("Aguardando a primeira sincronização", "Essa conta ainda não teve nenhuma sincronização concluída.") if @last_ok.nil?
      return warn("A última sincronização falhou", @last_finished.detail) if @last_finished && !@last_finished.ok
      return warn("Sincronização atrasada", "Última sincronização há #{minutes_ago} min") if delayed?

      { state: "ok", last_ok_at: @last_ok.finished_at, minutes_ago: minutes_ago, notice: nil }
    end

    private

    def delayed? = (Time.current - @last_ok.finished_at) > OK_WINDOW

    def minutes_ago
      return nil unless @last_ok

      ((Time.current - @last_ok.finished_at) / 60).round
    end

    def bad(title, body)
      { state: "bad", last_ok_at: @last_ok&.finished_at, minutes_ago: minutes_ago, notice: { title: title, body: body } }
    end

    def warn(title, body)
      { state: "warn", last_ok_at: @last_ok.finished_at, minutes_ago: minutes_ago, notice: { title: title, body: body } }
    end
  end
end
