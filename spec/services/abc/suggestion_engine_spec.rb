require "rails_helper"

RSpec.describe Abc::SuggestionEngine do
  def call(item: build_item, metric: build_metric, curve: nil, group: nil, price: { kind: "none" }, median: nil, params: abc_params)
    ctx = described_class::Context.new(item: item, metric: metric, curve: curve, group: group, price: price, conversion_median: median, params: params)
    described_class.call(ctx)
  end

  def find(suggestions, title) = suggestions.find { |s| s[:title] == title }

  # 1 — status pausado que vendeu nos últimos 60 dias
  it "pausado com venda nos últimos 60 dias -> reativar (prioridade 1)" do
    result = call(metric: build_metric(status: "paused", units_30d: 0, prev_units_30d: 1))
    expect(find(result, "Reativar anúncio")[:priority]).to eq(1)
  end

  it "pausado sem venda nos últimos 60 dias -> não sugere reativar" do
    result = call(metric: build_metric(status: "paused", units_30d: 0, prev_units_30d: 0))
    expect(find(result, "Reativar anúncio")).to be_nil
  end

  # 2 — em revisão
  it "em revisão -> resolver no painel do vendedor (prioridade 1)" do
    result = call(metric: build_metric(status: "under_review"))
    expect(find(result, "Resolver revisão do Mercado Livre")[:priority]).to eq(1)
  end

  # 3 — estoque zerado
  it "ativo sem estoque, fora do Full -> repor estoque (prioridade 1)" do
    result = call(metric: build_metric(status: "active", stock: 0, full: false))
    expect(find(result, "Repor estoque")[:priority]).to eq(1)
  end

  it "ativo sem estoque, no Full -> programar envio ao Full" do
    result = call(metric: build_metric(status: "active", stock: 0, full: true))
    expect(find(result, "Programar envio ao Full")[:priority]).to eq(1)
  end

  # 4 — cobertura 30d < 20 dias (só com estoque > 0)
  it "cobertura 9,9 dias -> prioridade 1" do
    result = call(metric: build_metric(stock: 5, coverage_30d: 9.9))
    expect(find(result, "Repor estoque em breve")[:priority]).to eq(1)
  end

  it "cobertura 10 dias -> prioridade 2" do
    result = call(metric: build_metric(stock: 5, coverage_30d: 10))
    expect(find(result, "Repor estoque em breve")[:priority]).to eq(2)
  end

  it "cobertura 19,9 dias -> prioridade 2" do
    result = call(metric: build_metric(stock: 5, coverage_30d: 19.9))
    expect(find(result, "Repor estoque em breve")[:priority]).to eq(2)
  end

  it "cobertura 20 dias -> não sugere" do
    result = call(metric: build_metric(stock: 5, coverage_30d: 20))
    expect(find(result, "Repor estoque em breve")).to be_nil
  end

  it "sem estoque (0), cobertura não se aplica" do
    result = call(metric: build_metric(stock: 0, coverage_30d: 5))
    expect(find(result, "Repor estoque em breve")).to be_nil
  end

  # 5 — preço sugerido abaixo do atual
  it "preço abaixo, status with_benchmark_highest -> prioridade 1" do
    item = build_item(price_ref: { "status" => "with_benchmark_highest" })
    result = call(item: item, price: { kind: "suggestion", diff_pct: -5.0 })
    expect(find(result, "Reduzir preço")[:priority]).to eq(1)
  end

  it "preço abaixo, conversão < 70% da mediana -> prioridade 1" do
    metric = build_metric(conversion_30d: 1.0)
    result = call(metric: metric, price: { kind: "suggestion", diff_pct: -5.0 }, median: 10.0)
    expect(find(result, "Reduzir preço")[:priority]).to eq(1)
  end

  it "preço abaixo, sem os agravantes -> prioridade 2" do
    metric = build_metric(conversion_30d: 8.0)
    result = call(metric: metric, price: { kind: "suggestion", diff_pct: -5.0 }, median: 10.0)
    expect(find(result, "Reduzir preço")[:priority]).to eq(2)
  end

  # 6 — preço sugerido acima do atual
  it "preço acima do atual, kind suggestion -> prioridade 2" do
    result = call(price: { kind: "suggestion", diff_pct: 5.0 })
    expect(find(result, "Avaliar aumento de preço")[:priority]).to eq(2)
  end

  it "kind aligned não sugere reduzir nem subir preço" do
    result = call(price: { kind: "aligned", diff_pct: 0.2 })
    expect(find(result, "Avaliar aumento de preço")).to be_nil
    expect(find(result, "Reduzir preço")).to be_nil
  end

  # 7 — exposição: curva A em queda, visitas caíram > 15%
  it "curva A em queda com visitas caindo mais de 15% -> prioridade 1" do
    metric = build_metric(visits_30d: 80, prev_visits_30d: 100)
    result = call(metric: metric, curve: "A", group: "down")
    expect(find(result, "Recuperar exposição")[:priority]).to eq(1)
  end

  it "curva A em queda sem queda de visitas -> não sugere recuperar exposição" do
    metric = build_metric(visits_30d: 95, prev_visits_30d: 100)
    result = call(metric: metric, curve: "A", group: "down")
    expect(find(result, "Recuperar exposição")).to be_nil
  end

  # 8 — conversão: curva A em queda, conversão < 80% da anterior
  it "curva A em queda com conversão caindo mais de 20% -> prioridade 1" do
    metric = build_metric(conversion_30d: 5.0, prev_conversion_30d: 10.0)
    result = call(metric: metric, curve: "A", group: "down")
    expect(find(result, "Investigar queda de conversão")[:priority]).to eq(1)
  end

  # 9 — conversão < 60% da mediana (ativo, >=100 visitas, fora do grupo em queda)
  it "99 visitas não entra na regra de conversão vs. mediana" do
    metric = build_metric(status: "active", visits_30d: 99, conversion_30d: 1.0)
    result = call(metric: metric, median: 10.0)
    expect(find(result, "Melhorar conversão")).to be_nil
  end

  it "100 visitas e conversão abaixo de 60% da mediana -> prioridade 2" do
    metric = build_metric(status: "active", visits_30d: 100, conversion_30d: 1.0)
    result = call(metric: metric, median: 10.0)
    expect(find(result, "Melhorar conversão")[:priority]).to eq(2)
  end

  it "não dispara dentro do grupo em queda da curva A (evita duplicar com a regra 8)" do
    metric = build_metric(status: "active", visits_30d: 100, conversion_30d: 1.0)
    result = call(metric: metric, curve: "A", group: "down", median: 10.0)
    expect(find(result, "Melhorar conversão")).to be_nil
  end

  # 10 — exposição: ativo com < 60 visitas em 30d
  it "59 visitas, curva C -> prioridade 1" do
    result = call(metric: build_metric(status: "active", visits_30d: 59), curve: "C")
    expect(find(result, "Aumentar exposição")[:priority]).to eq(1)
  end

  it "59 visitas, outra curva -> prioridade 2" do
    result = call(metric: build_metric(status: "active", visits_30d: 59), curve: "B")
    expect(find(result, "Aumentar exposição")[:priority]).to eq(2)
  end

  it "60 visitas -> não sugere aumentar exposição" do
    result = call(metric: build_metric(status: "active", visits_30d: 60))
    expect(find(result, "Aumentar exposição")).to be_nil
  end

  # 11 — título curto
  it "título com 39 caracteres -> prioridade 2" do
    result = call(metric: build_metric(title: "a" * 39))
    expect(find(result, "Ampliar título")[:priority]).to eq(2)
  end

  it "título com 40 caracteres -> não sugere" do
    result = call(metric: build_metric(title: "a" * 40))
    expect(find(result, "Ampliar título")).to be_nil
  end

  # 12 — marca ausente no título
  it "marca cadastrada e ausente do título -> prioridade 2" do
    item = build_item(brand: "Bosch")
    result = call(item: item, metric: build_metric(title: "Furadeira profissional para uso industrial pesado"))
    expect(find(result, "Incluir marca no título")[:priority]).to eq(2)
  end

  it "marca presente no título (case-insensitive) -> não sugere" do
    item = build_item(brand: "Bosch")
    result = call(item: item, metric: build_metric(title: "Furadeira BOSCH profissional para uso industrial"))
    expect(find(result, "Incluir marca no título")).to be_nil
  end

  it "sem marca cadastrada -> não sugere" do
    result = call(item: build_item(brand: nil))
    expect(find(result, "Incluir marca no título")).to be_nil
  end

  # 13 — modelo (> 2 caracteres) ausente, título < 55
  it "modelo ausente e título com 54 caracteres -> prioridade 3" do
    item = build_item(model: "GSB13")
    result = call(item: item, metric: build_metric(title: "a" * 54))
    expect(find(result, "Incluir modelo no título")[:priority]).to eq(3)
  end

  it "modelo ausente mas título com 55 caracteres -> não sugere" do
    item = build_item(model: "GSB13")
    result = call(item: item, metric: build_metric(title: "a" * 55))
    expect(find(result, "Incluir modelo no título")).to be_nil
  end

  it "modelo com 2 caracteres -> não sugere" do
    item = build_item(model: "X2")
    result = call(item: item, metric: build_metric(title: "a" * 30))
    expect(find(result, "Incluir modelo no título")).to be_nil
  end

  # 14 — termos proibidos (sem acento/caixa)
  it "título com termo proibido (com acento e maiúsculas) -> prioridade 1" do
    result = call(metric: build_metric(title: "Furadeira com FRETE GRÁTIS e ótima qualidade"))
    suggestion = find(result, "Remover termos não permitidos do título")
    expect(suggestion[:priority]).to eq(1)
    expect(suggestion[:why]).to include("frete gratis")
  end

  it "título sem termos proibidos -> não sugere" do
    result = call
    expect(find(result, "Remover termos não permitidos do título")).to be_nil
  end

  # 15 — atributos obrigatórios faltando (com detalhes carregados)
  it "atributos obrigatórios faltando, detalhes carregados -> prioridade 1 com os nomes" do
    item = build_item(attrs_missing_required: [ "Voltagem" ], details_checked_at: Time.current)
    result = call(item: item)
    suggestion = find(result, "Completar atributos obrigatórios")
    expect(suggestion[:priority]).to eq(1)
    expect(suggestion[:why]).to include("Voltagem")
  end

  it "atributos obrigatórios faltando, detalhes NÃO carregados -> não sugere (regra pulada)" do
    item = build_item(attrs_missing_required: [ "Voltagem" ], details_checked_at: nil)
    result = call(item: item)
    expect(find(result, "Completar atributos obrigatórios")).to be_nil
  end

  # 16 — características principais faltando
  it "características principais faltando -> prioridade 2" do
    item = build_item(attrs_missing_main: [ "Cor" ], details_checked_at: Time.current)
    result = call(item: item)
    suggestion = find(result, "Completar características principais")
    expect(suggestion[:priority]).to eq(2)
    expect(suggestion[:why]).to include("Cor")
  end

  # 17/18 — fotos
  it "2 fotos -> prioridade 1" do
    result = call(item: build_item(pictures_count: 2))
    expect(find(result, "Adicionar fotos")[:priority]).to eq(1)
  end

  it "3 fotos -> prioridade 2 (3 a 5)" do
    result = call(item: build_item(pictures_count: 3))
    expect(find(result, "Adicionar fotos")).to be_nil
    expect(find(result, "Adicionar mais fotos")[:priority]).to eq(2)
  end

  it "5 fotos -> prioridade 2" do
    result = call(item: build_item(pictures_count: 5))
    expect(find(result, "Adicionar mais fotos")[:priority]).to eq(2)
  end

  it "6 fotos -> não sugere nada sobre fotos" do
    result = call(item: build_item(pictures_count: 6))
    expect(find(result, "Adicionar fotos")).to be_nil
    expect(find(result, "Adicionar mais fotos")).to be_nil
  end

  # 19 — sem vídeo, curva A ou B
  it "sem vídeo, curva A -> prioridade 3" do
    result = call(item: build_item(has_video: false), curve: "A")
    expect(find(result, "Adicionar vídeo")[:priority]).to eq(3)
  end

  it "sem vídeo, curva C -> não sugere" do
    result = call(item: build_item(has_video: false), curve: "C")
    expect(find(result, "Adicionar vídeo")).to be_nil
  end

  # 20/21 — descrição
  it "sem descrição, detalhes carregados -> prioridade 1" do
    item = build_item(description_len: 0, details_checked_at: Time.current)
    result = call(item: item)
    expect(find(result, "Escrever descrição")[:priority]).to eq(1)
  end

  it "descrição com 399 caracteres -> prioridade 2" do
    item = build_item(description_len: 399, details_checked_at: Time.current)
    result = call(item: item)
    expect(find(result, "Ampliar descrição")[:priority]).to eq(2)
  end

  it "descrição com 400 caracteres -> não sugere" do
    item = build_item(description_len: 400, details_checked_at: Time.current)
    result = call(item: item)
    expect(find(result, "Ampliar descrição")).to be_nil
  end

  # 22 — Clássico, preço >= 120, curva A/B, ML recomenda parcelamento
  it "clássico caro em curva A com recomendação de parcelamento -> prioridade 3" do
    item = build_item(listing_type_id: "gold_special", quality_pending: [ { "key" => "INSTALLMENTS_RECOMMENDATION", "title" => "Parcelamento" } ])
    result = call(item: item, metric: build_metric(price: 150), curve: "A")
    expect(find(result, "Testar anúncio Premium")[:priority]).to eq(3)
  end

  it "clássico caro sem recomendação de parcelamento -> não sugere Premium" do
    item = build_item(listing_type_id: "gold_special", quality_pending: [])
    result = call(item: item, metric: build_metric(price: 150), curve: "A")
    expect(find(result, "Testar anúncio Premium")).to be_nil
  end

  # 23 — sem frete grátis, 60 <= preço < 79
  it "preço 59,99 sem frete grátis -> não sugere" do
    result = call(metric: build_metric(price: 59.99, free_shipping: false), item: build_item(free_shipping: false))
    expect(find(result, "Testar frete grátis")).to be_nil
  end

  it "preço 60 sem frete grátis -> prioridade 3" do
    result = call(metric: build_metric(price: 60, free_shipping: false), item: build_item(free_shipping: false))
    expect(find(result, "Testar frete grátis")[:priority]).to eq(3)
  end

  it "preço 78,99 sem frete grátis -> prioridade 3" do
    result = call(metric: build_metric(price: 78.99, free_shipping: false), item: build_item(free_shipping: false))
    expect(find(result, "Testar frete grátis")[:priority]).to eq(3)
  end

  it "preço 79 sem frete grátis -> não sugere" do
    result = call(metric: build_metric(price: 79, free_shipping: false), item: build_item(free_shipping: false))
    expect(find(result, "Testar frete grátis")).to be_nil
  end

  # 24 — fora do Full, curva A, >= 30 vendas/mês
  it "29 vendas fora do Full em curva A -> não sugere Full" do
    result = call(metric: build_metric(full: false, units_30d: 29), curve: "A")
    expect(find(result, "Avaliar Full")).to be_nil
  end

  it "30 vendas fora do Full em curva A -> prioridade 2" do
    result = call(metric: build_metric(full: false, units_30d: 30), curve: "A")
    expect(find(result, "Avaliar Full")[:priority]).to eq(2)
  end

  # 25 — recomendações pendentes do ML (sem repetir key)
  it "nota < 70 -> prioridade 2" do
    item = build_item(quality_score: 69, quality_pending: [ { "key" => "K1", "title" => "Melhorar título", "label" => "Título curto" } ])
    result = call(item: item)
    suggestion = find(result, "Melhorar título")
    expect(suggestion[:priority]).to eq(2)
    expect(suggestion[:why]).to eq("Título curto")
  end

  it "nota >= 70 -> prioridade 3" do
    item = build_item(quality_score: 70, quality_pending: [ { "key" => "K1", "title" => "Melhorar título", "label" => "Título curto" } ])
    result = call(item: item)
    expect(find(result, "Melhorar título")[:priority]).to eq(3)
  end

  it "não repete a mesma key" do
    item = build_item(quality_score: 50, quality_pending: [
      { "key" => "K1", "title" => "Melhorar título", "label" => "x" },
      { "key" => "K1", "title" => "Melhorar título de novo", "label" => "y" }
    ])
    result = call(item: item)
    expect(result.count { |s| s[:area] == "qualidade" }).to eq(1)
  end

  # 26 — curva C, ativo, sem venda no mês, >= 60 visitas
  it "curva C ativo sem venda com 60 visitas -> prioridade 2" do
    metric = build_metric(status: "active", units_30d: 0, visits_30d: 60)
    result = call(metric: metric, curve: "C")
    expect(find(result, "Avaliar liquidação ou unificação")[:priority]).to eq(2)
  end

  it "curva C ativo sem venda com 59 visitas -> não sugere" do
    metric = build_metric(status: "active", units_30d: 0, visits_30d: 59)
    result = call(metric: metric, curve: "C")
    expect(find(result, "Avaliar liquidação ou unificação")).to be_nil
  end

  # 27 — detalhes ainda não carregados
  it "detalhes não carregados -> prioridade 3 e pula descrição/ficha" do
    item = build_item(details_checked_at: nil, description_len: 0, attrs_missing_required: [ "Voltagem" ])
    result = call(item: item)

    expect(find(result, "Aguardar carregamento dos detalhes")[:priority]).to eq(3)
    expect(find(result, "Escrever descrição")).to be_nil
    expect(find(result, "Completar atributos obrigatórios")).to be_nil
  end

  it "detalhes carregados -> não sugere aguardar" do
    result = call(item: build_item(details_checked_at: Time.current))
    expect(find(result, "Aguardar carregamento dos detalhes")).to be_nil
  end

  # Ordenação estável: prioridade crescente, empate pela ordem da tabela
  it "ordena por prioridade e, no empate, pela ordem das regras" do
    item = build_item(pictures_count: 2, has_video: false) # regra 17 (prio 1) e regra 19 não se aplica sem curva A/B
    metric = build_metric(status: "under_review", title: "a" * 39) # regra 2 (prio 1) e regra 11 (prio 2)
    result = call(item: item, metric: metric)

    priorities = result.map { |s| s[:priority] }
    expect(priorities).to eq(priorities.sort)
    # regra 2 (moderação) vem antes da regra 17 (fotos) — ambas prioridade 1, moderação está antes na tabela
    prio1_titles = result.select { |s| s[:priority] == 1 }.map { |s| s[:title] }
    expect(prio1_titles.index("Resolver revisão do Mercado Livre")).to be < prio1_titles.index("Adicionar fotos")
  end
end
