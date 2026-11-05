# Relatório da rotina das 03:00 da seção Promoções: a lista de execuções com os totais e, de cada uma, o antes e o
# depois de cada anúncio (preço, margem e lucro), também em CSV.
require "csv"

module Painel
  module PromotionRunReport
    MODE_LABELS = { "simulation" => "Simulação", "apply" => "Aplicação real" }.freeze
    TRIGGER_LABELS = { "agendada" => "Agendada (03:00)", "manual" => "Simular agora", "aplicacao_manual" => "Aplicação manual" }.freeze
    RESULT_LABELS = {
      "aderir" => "Entraria / entrou", "trocar" => "Trocaria / trocou", "ajustar_preco" => "Ajustaria / ajustou o preço",
      "agendar" => "Entraria / entrou na próxima (começa depois)", "revisar" => "Para revisar", "pular" => "Não mexeu"
    }.freeze
    # ordem em que os anúncios aparecem no relatório
    KIND_ORDER = %w[trocar ajustar_preco aderir agendar revisar pular].freeze

    module_function

    def list(account, limit: 30)
      account.ml_promotion_runs.order(started_at: :desc).limit(limit).map { |run| summary(run) }
    end

    def summary(run)
      {
        id: run.id, mode: run.mode, mode_label: MODE_LABELS.fetch(run.mode, run.mode),
        trigger: run.trigger, trigger_label: TRIGGER_LABELS.fetch(run.trigger, run.trigger),
        status: run.status, started_at: run.started_at, finished_at: run.finished_at, error: run.error,
        totals: run.totals
      }
    end

    def detail(account, run_id)
      run = account.ml_promotion_runs.find(run_id)
      actions = run.actions.to_a
      items = account.ml_items.where(item_id: actions.map(&:item_id).uniq).pluck(:item_id, :title, :sku, :thumbnail)
        .to_h { |id, title, sku, thumb| [ id, { title: title, sku: sku, thumbnail: thumb } ] }
      rows = actions.map { |a| row(a, items[a.item_id] || {}) }
        .sort_by { |r| [ KIND_ORDER.index(r[:kind]) || 9, -(r[:gain] || -9999) ] }

      changed = rows.select { |r| r[:changes] && r[:ok] }
      summary(run).merge(
        gain_total: changed.sum { |r| r[:gain].to_f }.round(2),
        price_up: changed.count { |r| r[:price_change_pct].to_f.positive? },
        price_down: changed.count { |r| r[:price_change_pct].to_f.negative? },
        gain_up: changed.sum { |r| r[:gain].to_f.positive? ? r[:gain].to_f : 0.0 }.round(2),
        gain_down: changed.sum { |r| r[:gain].to_f.negative? ? r[:gain].to_f : 0.0 }.round(2),
        highlights: highlights(run, rows),
        rows: rows
      )
    end

    # Resumo em frases da rodada (pedido do usuário em 05/11/2026), o mesmo que o assistente escreve: quantos entraram,
    # trocaram, ajustaram, ficaram programados, sem mudança, para revisar, fora da automação e recusas do ML.
    def highlights(run, rows)
      sim = run.mode != "apply"
      t = run.totals || {}
      ok = rows.select { |r| r[:changes] && r[:ok] }
      now = ok.reject { |r| r[:effect]&.dig(:key) == "programada" }
      plural = ->(n, one, many) { "#{n} #{n == 1 ? one : many}" }
      lines = []
      if run.status == "failed"
        lines << "A rodada parou com erro: #{run.error}. Nada foi alterado no Mercado Livre depois do erro."
        return lines
      end
      joined = now.count { |r| r[:kind] == "aderir" }
      if joined.positive?
        empty = now.count { |r| r[:kind] == "aderir" && r[:before].nil? }
        lines << "#{plural.(joined, sim ? 'entraria' : 'entrou', sim ? 'entrariam' : 'entraram')} numa promoção" +
                 (empty.positive? ? " (#{empty} estava#{empty == 1 ? '' : 'm'} sem promoção, no preço cheio)." : ".")
      end
      switched = now.count { |r| r[:kind] == "trocar" }
      lines << "#{plural.(switched, sim ? 'trocaria' : 'trocou', sim ? 'trocariam' : 'trocaram')} por uma promoção melhor." if switched.positive?
      adjusted = now.count { |r| r[:kind] == "ajustar_preco" }
      lines << "#{plural.(adjusted, sim ? 'ajustaria' : 'ajustou', sim ? 'ajustariam' : 'ajustaram')} o preço na promoção atual." if adjusted.positive?
      scheduled = ok.size - now.size
      lines << "#{plural.(scheduled, sim ? 'ficaria programado' : 'ficou programado', sim ? 'ficariam programados' : 'ficaram programados')} para entrar quando a promoção atual acabar." if scheduled.positive?
      rest = [ [ "sem_mudanca", "sem mudança (já na melhor oferta)" ], [ "revisar", "para revisar" ],
               [ "automacao_desligada", "com automação desligada" ], [ "catalogo_fora", "de catálogo fora da automação" ],
               [ "regra_propria", "com regra própria" ] ]
        .filter_map { |k, label| t[k].to_i.positive? ? "#{t[k]} #{label}" : nil }
      lines << "#{rest.join(', ')}." if rest.any?
      failed = rows.count { |r| r[:changes] && !r[:ok] } + t["erro"].to_i
      lines << (failed.positive? ? "#{plural.(failed, 'anúncio teve', 'anúncios tiveram')} erro ou recusa do Mercado Livre (veja abaixo)." :
                                   (sim ? "Simulação: nada foi alterado no Mercado Livre." : "Nenhuma recusa do Mercado Livre."))
      lines.unshift("#{t['anuncios'].to_i} anúncios avaliados.")
    end

    def row(a, item)
      changes = %w[trocar ajustar_preco aderir agendar].include?(a.kind)
      {
        item_id: a.item_id, title: item[:title], sku: item[:sku], thumbnail: item[:thumbnail],
        kind: a.kind, kind_label: RESULT_LABELS.fetch(a.kind, a.kind), changes: changes, ok: a.ok,
        reason: a.error,
        before: a.from_type && { name: a.from_name, price: a.from_price&.to_f, margin_pct: a.from_margin_pct&.to_f, profit: a.from_profit&.to_f,
                                 start: a.from_start, finish: a.from_finish },
        after: a.to_type && { name: a.to_name, price: a.to_price&.to_f, margin_pct: a.to_margin_pct&.to_f, profit: a.to_profit&.to_f,
                              start: a.to_start, finish: a.to_finish },
        effect: changes && a.ok ? effect(a) : nil,
        price_change_pct: a.from_price.to_f.positive? && a.to_price ? ((a.to_price.to_f / a.from_price.to_f - 1) * 100).round(2) : nil,
        gain: a.gain&.to_f
      }
    end

    # Em vigor (aplicada na hora) ou Programada (passa a valer depois: a nova começa depois ou espera a atual acabar).
    def effect(a)
      if a.effective_at && a.effective_at > a.created_at + 1.minute
        { key: "programada", label: "Programada", at: a.effective_at }
      else
        { key: "em_vigor", label: "Em vigor", at: a.created_at }
      end
    end

    def period_text(start, finish)
      fmt = ->(t) { t.in_time_zone("America/Sao_Paulo").strftime("%d/%m %H:%M") }
      return nil if start.nil? && finish.nil?

      [ start && fmt.(start), finish && fmt.(finish) ].map { |x| x || "—" }.join(" até ")
    end

    def csv(account, run)
      data = detail(account, run.id)
      CSV.generate(col_sep: ";") do |out|
        out << [ "Execução", "Modo", "Anúncio", "Título", "SKU", "Resultado", "Promoção antes", "Preço antes", "Margem antes (%)",
                 "Lucro antes (R$)", "Promoção depois", "Preço depois", "Margem depois (%)", "Lucro depois (R$)",
                 "Variação do preço (%)", "Ganho por unidade (R$)", "Aplicação", "Passa a valer", "Período antes", "Período depois", "Motivo" ]
        data[:rows].each do |r|
          out << [ run.started_at.in_time_zone.strftime("%d/%m/%Y %H:%M"), data[:mode_label], r[:item_id], r[:title], r[:sku],
                   r[:ok] ? r[:kind_label] : "Falhou", r.dig(:before, :name), num(r.dig(:before, :price)), num(r.dig(:before, :margin_pct)),
                   num(r.dig(:before, :profit)), r.dig(:after, :name), num(r.dig(:after, :price)), num(r.dig(:after, :margin_pct)),
                   num(r.dig(:after, :profit)), num(r[:price_change_pct]), num(r[:gain]), r.dig(:effect, :label),
                   r.dig(:effect, :at)&.in_time_zone("America/Sao_Paulo")&.strftime("%d/%m/%Y %H:%M"),
                   period_text(r.dig(:before, :start), r.dig(:before, :finish)), period_text(r.dig(:after, :start), r.dig(:after, :finish)),
                   r[:reason] ]
        end
      end
    end

    def num(v) = v.nil? ? nil : format("%.2f", v.to_f).tr(".", ",")
  end
end
