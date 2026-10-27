# Cancelamento, reclamação e devolução de uma venda, em texto para a seção Vendas.
# Lê o cancel_detail do pedido e as reclamações já resumidas por Ml::Sync::Claims (ml_orders.claims).
module Painel
  module SaleIssues
    WHO = { "buyer" => "comprador", "seller" => "vendedor", "meli" => "Mercado Livre", "receiver" => "comprador",
            "sender" => "vendedor" }.freeze

    CANCEL_CODES = {
      "buyer_cancel_express" => "Comprador cancelou antes do envio",
      "mediations" => "Cancelada por reclamação",
      "shipment_not_delivered" => "Envio não entregue",
      "shipment_operative_issue" => "Problema operacional no envio",
      "feedback_out_of_stock" => "Vendedor sem estoque",
      "fraud" => "Suspeita de fraude",
      "pack_splitted" => "Carrinho dividido em outras vendas"
    }.freeze

    CLAIM_TYPES = {
      "mediations" => "Reclamação", "cancel_purchase" => "Cancelamento pelo comprador",
      "cancel_sale" => "Cancelamento pelo vendedor", "returns" => "Devolução", "change" => "Troca"
    }.freeze

    STAGES = { "claim" => "com o vendedor", "dispute" => "em mediação do ML", "recontact" => "recontato" }.freeze

    RESOLUTIONS = {
      "coverage_decision" => "decisão do Mercado Livre", "prefered_to_keep_product" => "comprador ficou com o produto",
      "item_returned" => "produto devolvido", "payment_refunded" => "comprador reembolsado",
      "partial_refunded" => "reembolso parcial", "already_shipped" => "produto já enviado",
      "seller_explained_functions" => "vendedor explicou o uso", "respondent_timeout" => "vendedor não respondeu no prazo",
      "low_cost" => "valor baixo, reembolsado pelo ML", "product_delivered" => "produto entregue",
      "timeout" => "prazo encerrado", "warehouse_decision" => "decisão do Full"
    }.freeze

    BENEFITED = { "complainant" => "a favor do comprador", "respondent" => "a favor do vendedor" }.freeze

    RETURN_STATUS = {
      "pending" => "aguardando o comprador enviar", "label_generated" => "etiqueta gerada", "shipped" => "a caminho do vendedor",
      "delivered" => "entregue ao vendedor", "cancelled" => "cancelada", "closed" => "encerrada", "expired" => "expirada",
      "failed" => "falhou", "not_delivered" => "não entregue"
    }.freeze

    MONEY = { "retained" => "dinheiro retido", "refunded" => "reembolsado ao comprador", "available" => "liberado ao vendedor" }.freeze

    module_function

    # => nil (venda sem problema) ou { label:, tone:, cancellation:, claims: [...] }
    def for(order)
      cancellation = cancellation(order)
      claims = Array(order.try(:claims)).reject { |c| c["status"] == "unavailable" }.map { |c| claim(c) }
      return nil if cancellation.nil? && claims.empty?

      { label: summary_label(cancellation, claims), tone: tone(order, claims), cancellation: cancellation, claims: claims }
    end

    def cancellation(order)
      return nil unless order.status == "cancelled"

      detail = (order.has_attribute?(:cancel_detail) ? order[:cancel_detail] : (order.payload || {})["cancel_detail"]) || {}
      who = WHO[detail["requested_by"]]
      {
        code: detail["code"], label: CANCEL_CODES.fetch(detail["code"], "Venda cancelada"),
        requested_by: who, date: detail["date"]
      }
    end

    def claim(c)
      resolution = c["resolution"] || {}
      benefited = Array(resolution["benefited"])
      devolution = c["return"]
      {
        id: c["id"], type: c["type"], label: CLAIM_TYPES.fetch(c["type"], "Reclamação"),
        reason: c["reason"], opened_by: WHO[c["opened_by"]],
        status: c["status"], open: c["status"] == "opened",
        stage: STAGES[c["stage"]],
        date: c["date_created"],
        resolution: resolution.presence && {
          label: RESOLUTIONS.fetch(resolution["reason"], resolution["reason"].to_s.tr("_", " ")),
          benefited: benefited.size == 2 ? "a favor dos dois" : BENEFITED[benefited.first],
          coverage: resolution["applied_coverage"] == true,
          closed_by: WHO.merge("complainant" => "comprador", "respondent" => "vendedor", "mediator" => "Mercado Livre")[resolution["closed_by"]],
          date: resolution["date_created"]
        },
        return: devolution && {
          status: devolution["status"], label: RETURN_STATUS.fetch(devolution["status"], devolution["status"].to_s),
          money: MONEY[devolution["status_money"]], total: devolution["subtype"] != "return_partial",
          tracking_number: Array(devolution["shipments"]).first&.dig("tracking_number"),
          date: devolution["date_created"]
        }
      }
    end

    # Texto curto para a lista: o que aconteceu e o motivo.
    def summary_label(cancellation, claims)
      main = claims.find { |c| c[:open] } || claims.find { |c| c[:return] } || claims.first
      parts = []
      if cancellation
        parts << cancellation[:label]
      elsif main
        parts << "#{main[:label]} #{main[:open] ? "aberta" : "encerrada"}"
      end
      parts << main[:reason] if main && main[:reason].present?
      parts << "devolução #{main[:return][:label]}" if main && main[:return]
      parts.join(" · ")
    end

    def tone(order, claims)
      return "bad" if order.status == "cancelled" || claims.any? { |c| c[:open] }

      "warn"
    end
  end
end
