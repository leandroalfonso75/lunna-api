# SPEC 9 — monta o prompt do plano de ação com IA. `detail` é o hash 10.6
# (Abc::Report#show), `row` o hash 10.5 do mesmo anúncio (Abc::Report#show
# via prompt_context) e `context` os campos extras que não estão em nenhum
# dos dois (marca, modelo, atributos faltando, recomendações do ML, frete
# grátis, imposto %, margem mínima, mediana da loja). Serviço puro — só
# monta texto/hash, não chama a Claude API.
module Ai
  class ActionPlanPrompt
    def self.call(detail, row, context) = new(detail, row, context).call

    def initialize(detail, row, context)
      @detail = detail
      @row = row
      @context = context
    end

    def call
      { system: system_prompt, user: data.to_json }
    end

    private

    def before_cost? = !!@detail.dig(:month, :profit_is_before_cost)

    def system_prompt
      text = +<<~TEXT
        Você é um especialista em vendas no Mercado Livre Brasil.
        Use somente os dados enviados abaixo — nunca invente números que não estejam neles.
        Siga as políticas do Mercado Livre: título com até 60 caracteres, sem termos promocionais ou de frete; foto de capa com fundo branco, sem texto ou logotipo; descrição sem links ou contatos; ficha técnica completa.

        Responda em texto simples, com estas 5 seções numeradas:
        1. Diagnóstico em 2 frases.
        2. Até 5 ações priorizadas (o quê, por quê, impacto).
        3. Título sugerido (até 60 caracteres) e 2 alternativas.
        4. Estrutura da descrição e fotos que faltam.
        5. Preço: manter, subir ou reduzir; com custo cadastrado, informe a margem resultante e alerte se ficar abaixo da margem mínima; sem custo cadastrado, informe o custo máximo (max_cost) que mantém a margem mínima.
      TEXT

      return text unless before_cost?

      text << "\nEste anúncio não tem custo cadastrado: o lucro informado é o lucro antes do custo. Deixe isso explícito e informe o custo máximo (max_cost) na seção de preço.\n"
    end

    def data
      unit = @detail[:unit]
      month = @detail[:month]
      indicators = @detail[:indicators]
      listing = @detail[:listing]
      price = @detail[:price]

      {
        title: @row[:title], sku: @row[:sku], status: @row[:status_label],
        curve: @row[:curve], group: @row[:group],
        price: unit[:price], full_price: unit[:full_price],
        listing_type: listing[:listing_type_label], full: @row[:full], free_shipping: @context[:free_shipping],
        stock: listing[:stock],
        visits_30d: indicators[:visits], prev_visits_30d: indicators[:prev_visits],
        units_30d: indicators[:units], prev_units_30d: indicators[:prev_units],
        conversion_30d: indicators[:conversion], conversion_median: @context[:conversion_median],
        revenue_30d: indicators[:revenue],
        fee_per_unit: unit[:fee], shipping_per_unit: unit[:shipping],
        tax_pct: @context[:tax_pct], cost: unit[:cost], min_margin_pct: @context[:min_margin_pct],
        profit_month: month[:profit], profit_is_before_cost: month[:profit_is_before_cost],
        pictures: listing[:pictures], has_video: listing[:has_video], description_len: listing[:description_len],
        quality_score: listing[:quality_score],
        brand: @context[:brand], model: @context[:model],
        attrs_missing_required: @context[:attrs_missing_required], attrs_missing_main: @context[:attrs_missing_main],
        quality_pending: @context[:quality_pending],
        price_ref: {
          suggested: price[:suggested], diff_pct: price[:diff_pct], status_text: price[:status_text],
          margin_pct: price[:margin_pct], max_cost: price[:max_cost], competitors: price[:competitors]
        },
        suggestions: @detail[:suggestions]
      }
    end
  end
end
