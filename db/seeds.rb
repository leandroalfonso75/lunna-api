# Seed de DESENVOLVIMENTO — só roda com RAILS_ENV=development (guard logo
# abaixo). Idempotente: pode rodar `bin/rails db:seed` várias vezes sem
# duplicar nada (upsert/find_or_create_by por chave natural).
#
# Cria a empresa "Lunna Demo", dois usuários e uma conta ML fake com ~40
# anúncios variados, 60 dias de visitas e pedidos (pagos e cancelados,
# gerados com Random.new(42) — determinístico) cobrindo os 7 alertas do
# painel (SPEC 7.5), e chama Painel::ItemMetrics.refresh no fim. Nunca fala
# com a API real do Mercado Livre — tokens e IDs são fictícios.
return unless Rails.env.development?

rng = Random.new(42)

# Referência de preço fictícia no formato gravado pela sync (SPEC 5).
def demo_price_ref(price, n)
  status, factor = [ [ "with_benchmark_highest", 0.86 ], [ "with_benchmark_high", 0.93 ],
                     [ "no_benchmark_ok", 1.0 ], [ "no_benchmark_lowest", 1.08 ] ][n % 4]
  suggested = (price * factor).round(2)
  graph = (1..6).map { |i| { "p" => (suggested * (0.9 + i * 0.04)).round(2), "t" => "Concorrente #{i} — similar", "s" => 40 * i } }
  { "status" => status, "current" => price, "suggested" => suggested, "lowest" => graph.first["p"],
    "pct" => ((suggested - price) / price * 100).round(1), "applicable" => true, "compared" => graph.size,
    "graph" => graph, "updated" => Time.current.iso8601 }
end

PRODUCT_NAMES = [
  "Luminária de Mesa LED Recarregável Touch 3 Cores", "Kit 2 Velas Aromáticas Lavanda e Baunilha 180g",
  "Porta-Retrato de Madeira Maciça 15x21 Natural", "Caneca de Cerâmica Lua Crescente 350ml",
  "Abajur Infantil Nuvem com Luz Noturna", "Difusor de Aromas Ultrassônico 300ml Madeira",
  "Jogo de Lençol Queen 400 Fios Algodão Egípcio", "Almofada Decorativa Linho 45x45 com Enchimento",
  "Organizador de Maquiagem Acrílico Giratório", "Espelho Redondo Decorativo 60cm Moldura Dourada",
  "Tapete Sala Shaggy 2x1,5m Cinza", "Cortina Blackout 2,80x2,30 Tecido Linho",
  "Relógio de Parede Minimalista 30cm Silencioso", "Vaso de Cerâmica Fosco Branco Médio",
  "Kit Toalhas de Banho 4 Peças Fio Penteado", "Cesto Organizador Fibra Natural com Alça",
  "Fita LED 5m RGB Wi-Fi Controle por App", "Umidificador de Ar 2,5L Silencioso Bivolt",
  "Quadro Decorativo Abstrato 60x40 Moldura Preta", "Prateleira Flutuante MDF 60cm Kit 3",
  "Garrafa Térmica Inox 1L Mantém 24h", "Jogo de Panelas Antiaderente 5 Peças Cerâmica",
  "Porta-Temperos Giratório 12 Potes Vidro", "Tábua de Corte Bambu Grande com Canaleta",
  "Kit Potes Herméticos Vidro 10 Peças", "Luminária Pendente Industrial Preta E27",
  "Cabideiro de Chão Madeira com Sapateira", "Manta Sofá Tricô 1,50x2,00 Off White",
  "Sapateira Organizadora 30 Pares Empilhável", "Lixeira Inox Pedal 12L Cozinha",
  "Suporte Notebook Ajustável Alumínio", "Mouse Pad Grande 90x40 Borda Costurada",
  "Kit Pincéis de Maquiagem 12 Peças com Estojo", "Escova Secadora 3 em 1 1200W Bivolt",
  "Chaleira Elétrica Inox 1,8L Desligamento Automático", "Balança Digital Cozinha 10kg Vidro",
  "Organizador de Gaveta Modular 8 Peças", "Varal de Chão Retrátil Alumínio 20m",
  "Travesseiro Nasa Viscoelástico Cervical", "Kit Jardinagem 10 Peças com Bolsa"
].freeze

today = Date.current
sp_now = Time.current.in_time_zone("America/Sao_Paulo")

company = Company.find_or_create_by!(name: "Lunna Demo")

User.find_or_create_by!(email: "demo@lunna.dev") do |user|
  user.company = company
  user.name = "Admin Demo"
  user.password = "lunna12345"
  user.role = "admin"
end

User.find_or_create_by!(email: "membro@lunna.dev") do |user|
  user.company = company
  user.name = "Membro Demo"
  user.password = "lunna12345"
  user.role = "member"
end

account = MlAccount.find_or_create_by!(seller_id: 999_000_111) do |acc|
  acc.company = company
  acc.nickname = "LUNNA_DEMO"
  acc.access_token = "demo-access-token"
  acc.refresh_token = "demo-refresh-token"
  acc.expires_at = 1.year.from_now
  acc.scope = "offline_access read"
  acc.status = "active"
  acc.orders_backfilled_at = Time.current
  acc.visits_synced_at = Time.current
end

# ---- anúncios ----
# Os 7 primeiros são desenhados pra disparar, cada um, um dos 7 alertas da
# SPEC 7.5; os 33 seguintes só dão variedade (status, tipo, Full, SKU,
# qualidade, com/sem desconto e preço de referência).
QUALITY_RULES = [
  { area: "images", key: "main_image", title: "Foto principal", label: "Adicione uma foto de capa melhor", mode: "recommended" },
  { area: "description", key: "length", title: "Descrição curta", label: "Capriche na descrição do produto", mode: "recommended" }
].freeze

def quality_pending_for(score)
  return [] if score >= 90

  QUALITY_RULES.first(score < 70 ? 2 : 1)
end

scenarios = [
  # nostock: ativo, estoque zerado.
  { status: "active", stock: 0, quality: 85, week: 6, prev_week: 6, today: 0, month_extra: 10 },
  # under_review.
  { status: "under_review", stock: 12, quality: 55, week: 1, prev_week: 1, today: 0, month_extra: 2 },
  # sales_drop: pu7 - u7 = 6 (>= 3).
  { status: "active", stock: 20, quality: 85, week: 2, prev_week: 8, today: 0, month_extra: 15 },
  # low_coverage: estoque 5, u7 14 -> cobertura = 5 / (14/7) = 2.5 dias (< 14).
  { status: "active", stock: 5, quality: 85, week: 14, prev_week: 12, today: 1, month_extra: 20 },
  # visits_no_sales: v7 >= 30 e u7 = 0.
  { status: "active", stock: 15, quality: 85, week: 0, prev_week: 0, today: 0, month_extra: 0, visits_per_day: 8 },
  # low_quality: nota < 70.
  { status: "active", stock: 10, quality: 45, week: 3, prev_week: 3, today: 0, month_extra: 5 },
  # paused_selling: pausado e vendia (pu7 > 0).
  { status: "paused", stock: 8, quality: 80, week: 0, prev_week: 5, today: 0, month_extra: 0 }
]

33.times do
  status = %w[active active active active paused closed closed inactive].sample(random: rng)
  has_recent_sales = status.in?(%w[active paused]) || rng.rand < 0.4
  scenarios << {
    status: status,
    stock: rng.rand(0..80),
    quality: rng.rand(25..99),
    week: has_recent_sales ? rng.rand(0..20) : 0,
    prev_week: has_recent_sales ? rng.rand(0..20) : 0,
    today: rng.rand(0..2),
    month_extra: has_recent_sales ? rng.rand(0..15) : 0
  }
end

item_rows = []
visit_rows = []
order_rows = {}
order_item_rows = []
order_seq = 3_500_000_000

scenarios.each_with_index do |scenario, index|
  n = index + 1
  item_id = format("MLB9%08d", n)
  sku = n.odd? ? format("SKU-DEMO-%03d", n) : nil
  listing_type_id = n.even? ? "gold_pro" : "gold_special"
  full = n % 3 != 0
  price = (29.9 + rng.rand(0..870)).round(2)
  discounted = n % 4 == 0
  original_price = discounted ? (price * 1.2).round(2) : nil
  quality_score = scenario[:quality]
  details_loaded = index < 34 # "a maioria" — deixa uns poucos sem detalhe carregado

  item_rows << {
    item_id: item_id, ml_account_id: account.id, seller_id: account.seller_id,
    title: PRODUCT_NAMES[(n - 1) % PRODUCT_NAMES.size],
    status: scenario[:status], sub_status: [],
    price: price, original_price: original_price, sale_price: nil, regular_price: original_price,
    available_quantity: scenario[:stock], sold_quantity: scenario[:week] + scenario[:prev_week],
    listing_type_id: listing_type_id, category_id: "MLB1234",
    logistic_type: full ? "fulfillment" : "drop_off", free_shipping: full || n.even?,
    catalog_listing: n % 5 == 0, sku: sku, variations_count: n % 6 == 0 ? 2 : 1,
    permalink: "https://produto.mercadolivre.com.br/#{item_id}", thumbnail: nil,
    health: 0.9, pictures_count: details_loaded ? [ 2, 4, 5, 7, 9 ][n % 5] : 1, has_video: n % 7 == 0,
    attrs_filled: details_loaded ? [ "BRAND", "MODEL" ] : [],
    attrs_missing_required: details_loaded ? [] : [ "BRAND" ],
    attrs_missing_main: [], brand: "Lunna", model: "Modelo #{n}",
    description_len: details_loaded ? [ 0, 180, 420, 950, 1600 ][n % 5] : 0,
    quality_score: quality_score, quality_level: quality_score >= 80 ? "green" : (quality_score >= 60 ? "yellow" : "red"),
    quality_pending: quality_pending_for(quality_score),
    # Tarifa ~ Premium 16,5% / Clássico 12% (+ R$ 6,50 abaixo de R$ 79); frete pago pelo vendedor.
    fee_now: (price * (listing_type_id == "gold_pro" ? 0.165 : 0.12) + (price < 79 ? 6.5 : 0)).round(2),
    ship_cost: (full || n.even?) ? (18 + (n % 6) * 3).to_f : (5 + n % 4).to_f,
    price_ref: details_loaded && n % 3 == 0 ? demo_price_ref(price, n) : nil,
    fee_at_ref: nil, ship_at_ref: nil,
    date_created: (400 - n).days.ago, last_updated: 1.day.ago,
    details_checked_at: details_loaded ? 1.hour.ago : nil,
    quality_checked_at: details_loaded ? 2.hours.ago : nil,
    synced_at: Time.current
  }

  # 60 dias de visitas (SPEC: dia = string do ML, sem conversão de fuso).
  visits_today = scenario[:visits_per_day] || rng.rand(0..20)
  (0..59).each do |days_ago|
    visit_rows << { item_id: item_id, ml_account_id: account.id, day: today - days_ago, visits: [ visits_today + rng.rand(-3..3), 0 ].max }
  end

  # Pedidos pagos: hoje, ao longo da semana atual, da anterior e do resto do mês.
  place = lambda do |quantity, days_ago, status: "paid"|
    next if quantity <= 0

    order_seq += 1
    at = (sp_now - days_ago.days).change(hour: 10 + (order_seq % 8))
    order_rows[order_seq] = { order_id: order_seq, ml_account_id: account.id, status: status,
      date_created: at, date_closed: at, total_amount: (price * quantity).round(2), synced_at: Time.current }
    order_item_rows << { order_id: order_seq, item_id: item_id, quantity: quantity, unit_price: price,
      sale_fee: (price * 0.11).round(2) }
  end

  place.call(scenario[:today], 0)
  place.call(scenario[:week], rng.rand(1..7))
  place.call(scenario[:prev_week], rng.rand(8..14))
  place.call(scenario[:month_extra], rng.rand(15..30))

  # Mês anterior (D−60..D−31) com tendência variada, para a Curva A ter os três
  # grupos (vendendo, estagnados, em queda) em vez de todo mundo "novo".
  month_now = scenario[:week] + scenario[:prev_week] + scenario[:month_extra]
  factor = { 0 => 0.6, 1 => 1.0, 2 => 1.7 }[n % 3]
  place.call((month_now * factor).round, rng.rand(31..59))
  place.call(rng.rand(1..3), rng.rand(1..7), status: "cancelled") if n.even? # pedido cancelado não conta nas métricas
end

MlItem.upsert_all(item_rows, unique_by: :item_id)
visit_rows.each_slice(500) { |batch| MlItemVisit.upsert_all(batch) } # PK composta (item_id, day) inferida
order_rows.values.each_slice(200) { |batch| MlOrder.upsert_all(batch, unique_by: :order_id) }
order_item_rows.each_slice(200) { |batch| MlOrderItem.upsert_all(batch) } # PK composta (order_id, item_id) inferida

# Custo pra metade dos SKUs (pra Curva ABC do A5 mostrar lucro líquido).
skus = item_rows.filter_map { |row| row[:sku] }
price_by_sku = item_rows.to_h { |row| [ row[:sku], row[:price] ] }
skus.each_slice(2).map(&:first).compact.each_with_index do |sku, i|
  # Custo entre ~38% e ~56% do preço (alguns ficam abaixo da margem mínima).
  cost = (price_by_sku[sku].to_f * (0.38 + (i % 4) * 0.06)).round(2)
  MlCost.upsert_all(
    [ { company_id: company.id, sku: sku, cost: cost, extra: 3.5, source: "seed", created_at: Time.current, updated_at: Time.current } ],
    unique_by: [ :company_id, :sku ]
  )
end

unless account.ml_sync_runs.where(ok: true).where("started_at > ?", 1.hour.ago).exists?
  account.ml_sync_runs.create!(started_at: 2.minutes.ago, finished_at: 1.minute.ago, ok: true,
    items: item_rows.size, orders: order_rows.size, detail: "seed de desenvolvimento")
end

Painel::ItemMetrics.refresh(account, today: today)

puts "Seed Lunna Demo pronto: empresa=#{company.id} conta=#{account.id} anúncios=#{item_rows.size}"
