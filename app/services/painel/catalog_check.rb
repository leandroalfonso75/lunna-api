# Anúncio de catálogo na automação de Promoções ("Incluir anúncios de catálogo na automação"):
#   1. uma hora depois de a rotina (ou o lote) mudar o preço, confere no ML se o anúncio está ganhando o catálogo;
#   2. se não está, volta ao preço anterior (a promoção de antes, no preço de antes, ou sai da promoção) e confere
#      de novo depois de uma hora;
#   3. se ainda não ganha, fica para análise manual (aviso na tela de Promoções).
module Painel
  class CatalogCheck
    WINNING = %w[winning sharing_first_place].freeze
    WAIT = 1.hour

    def self.schedule(account, item, action)
      check = account.ml_catalog_checks.create!(item_id: item.item_id, action: action, status: "aguardando", check_at: WAIT.from_now)
      Ml::CatalogCheckJob.set(wait: WAIT).perform_later(check.id)
      check
    end

    def self.call(check) = new(check).call

    def initialize(check)
      @check = check
      @account = check.ml_account
    end

    def call
      return @check unless %w[aguardando revertido].include?(@check.status)

      Ml::OAuth.refresh!(@account)
      client = Ml::Client.new(access_token: @account.access_token)
      ml_status = client.price_to_win(@check.item_id)["status"].to_s
      @check.update!(ml_status: ml_status, checked_at: Time.current, attempts: @check.attempts + 1)

      if WINNING.include?(ml_status)
        @check.update!(status: @check.status == "revertido" ? "resolvido" : "ganhando",
                       message: @check.status == "revertido" ? "voltou ao preço anterior e está ganhando" : "ganhando o catálogo")
      elsif @check.status == "aguardando"
        revert
      else
        @check.update!(status: "analise_manual", message: "não ganha o catálogo nem no preço anterior (#{ml_status.presence || 'sem status'})")
      end
      @check
    rescue Ml::OAuth::Error, Ml::Client::Error => e
      @check.update!(status: "analise_manual", checked_at: Time.current, message: "não deu para conferir no ML: #{e.message.truncate(150)}")
      @check
    end

    private

    # Volta ao que era antes da mudança: a promoção anterior no preço anterior, ou sem promoção.
    def revert
      a = @check.action
      result = if a&.from_type.present?
        PromotionActions.apply(@account, @check.item_id, source: "catalogo",
          target: { promotion_id: a.from_promotion_id, promotion_type: a.from_type, price: a.from_price&.to_f, force: true })
      else
        PromotionActions.leave(@account, @check.item_id, source: "catalogo")
      end
      unless result.ok
        return @check.update!(status: "analise_manual", message: "não ganha o catálogo e não deu para voltar ao preço anterior: #{result.message.truncate(150)}")
      end

      @check.update!(status: "revertido", check_at: CatalogCheck::WAIT.from_now, message: "não ganhava o catálogo: voltou ao preço anterior")
      Ml::CatalogCheckJob.set(wait: CatalogCheck::WAIT).perform_later(@check.id)
    end
  end
end
