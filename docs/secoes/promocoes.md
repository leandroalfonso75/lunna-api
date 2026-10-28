# Promoções

Promoções da **Central de Promoções do Mercado Livre** por anúncio: a promoção atual, a melhor oferta disponível
(maior margem dentro da margem mínima e máxima) e o ganho da troca. Proposta completa e fases:
[Seção Promoções do Lunna: proposta](https://claude.ai/artifact/524x29CDnNHJy2wo7rrwEg).

Fase 1 (pronta): ver, comparar, configurar margens e exportar. Fase 2 (pronta): aplicar a melhor oferta, entrar numa
oferta, ajustar o preço e sair, por anúncio ou em lote, **só administradores e sempre com confirmação na tela**. Fase 3
(rotina das 03:00) ainda não existe.

## O que a tela mostra
- **Cartões:** anúncios em promoção, sem promoção, trocas que rendem mais (com o ganho somado por unidade) e abaixo
  da margem mínima.
- **Aba Anúncios:** as variações de um produto (mesmo produto pai no Olist) ficam agrupadas numa linha do produto, com
  o nome do pai, quantas variações e anúncios, faixa de preço e a situação mais urgente; clicando, abrem os anúncios
  dentro. "Limites do produto" grava os limites em todas as variações e nos anúncios do mesmo SKU. Anúncio sem pai
  fica numa linha própria. As guias de situação mostram a contagem de anúncios entre parênteses. Um anúncio ativo por linha, com preço cheio, promoção atual (preço, margem e lucro por unidade),
  melhor oferta, ganho por unidade e situação: Trocar por melhor, Sem promoção, Abaixo da mínima, Na melhor, Sem custo.
  Filtros por situação, por promoção e busca por anúncio, título ou SKU.
- **Painel do anúncio (clique na linha):** todas as ofertas do anúncio com preço, parte do ML, tarifa e margem (a
  melhor marcada) e o formulário de margem mínima e máxima, com "aplicar aos outros anúncios do SKU".
- **Aba Promoções do ML:** cada promoção da Central com tipo, situação, período, anúncios ativos e candidatos;
  "Ver anúncios" filtra a aba Anúncios por ela.
- **Levar a mesma promoção ao produto:** na confirmação de entrar/trocar, dá para marcar "aplicar aos outros anúncios
  do SKU" e "às variações do produto"; eles vão para a fila (`PromotionActions.extend_to_related`), cada um pelo seu
  preço e seus limites.
- **Aplicar (administrador):** no painel do anúncio, "Aplicar a melhor oferta", "Entrar"/"Ajustar" em cada oferta e
  "Sair da promoção"; cada um mostra antes o que vai acontecer (de onde sai, para onde vai, preço e margem) e só age
  depois de "Confirmar". Na lista, marcar anúncios (ou "Marcar os desta página que podem melhorar") e "Aplicar a melhor
  oferta nos marcados": vai para a fila (`Ml::PromotionsApplyJob`), um anúncio de cada vez.
- **Aba Histórico:** cada ação (pela tela, em lote ou pela rotina) com de/para, preço, margem, ganho, quem e o
  resultado do ML.
- **Exportar todas (CSV):** uma linha por anúncio e oferta (ativa ou candidata), com preços, faixa, parte do ML,
  margem e lucro. Separador `;` e vírgula decimal, para abrir direto no Excel.

## Regras
- **Margem da oferta** (`Painel::PromotionEvaluator`), sempre **pós Ads** ("margem real" e "lucro real" na tela):
  lucro = preço + parte do ML − custo − tarifa − frete − imposto − despesas fixas − Ads; margem = lucro ÷ preço.
  - Ads: custo de Ads por unidade do anúncio nos últimos 15 dias fechados = gasto (`ml_ad_item_dailies`) ÷ unidades
    vendidas no mesmo período (vendas não canceladas). Sem gasto, ou gasto sem venda, vale zero (a tela mostra o gasto).
  - O painel do anúncio mostra os custos por unidade linha a linha, hoje e depois da melhor oferta.
  - Parte do ML: ofertas com desconto dividido (`meli_percentage`) — o ML banca esse % do preço original.
  - Tarifa: a do ML no preço da oferta (`/sites/MLB/listing_prices`, guardada em `ml_promotion_offers.fees`); em outro
    preço, % da tarifa × preço + taxa fixa.
  - Frete, custo, imposto e despesas fixas: os mesmos da seção Anúncios.
- **Preço da oferta:** fixo (SMART, PRICE_MATCHING, relâmpago com ML, DOD) ou, nas de faixa (campanha do vendedor,
  DEAL, desconto próprio, relâmpago), o maior preço permitido. Com margem máxima, desce o preço até ela.
- **O preço cheio do anúncio nunca muda** e é o teto (`price_cap`): a promoção parte dele e o preço final fica abaixo
  dele. O preço final pode subir ou descer em relação ao de hoje (cheio 100, promoção a 90, pode ir a 92), dentro dos
  limites. Motivo: acima de R$ 79 o frete grátis é obrigatório e pago pelo vendedor. As margens mínima e máxima (ou os valores)
  são os limites do preço de venda depois do desconto: oferta abaixo da mínima ou acima da máxima não serve, inclusive a
  atual ("Acima da máxima" pede um desconto maior).
- **Aumento do preço de venda limitado por faixa**, sempre em relação à última promoção (o preço de hoje): acima de
  R$ 200 até 2%; de R$ 100 a R$ 199,99 até 3%; de R$ 50 a R$ 99,99 até 5%; de R$ 10 a R$ 49,99 até 7% (abaixo de R$ 10
  também 7%). Mesmo dentro do limite, o preço não passa para a casa de cem seguinte (198 não vira 201: fica em 199,99).
  Oferta de preço fixo acima do limite não serve; nas de faixa, o preço para no limite. Motivo: aumento de preço é mal
  visto pelo marketplace e derruba a conversão.
- **Para revisar:** anúncio em que nenhuma oferta cabe nas regras e a promoção atual também não (ou não há promoção).
  Nada é aplicado; a guia vermelha "Para revisar" lista cada um com a regra que barrou a atual e as que barraram as
  ofertas (`review` na API).
- **Limites por margem ou por valor** (`limit_mode`, um desabilita o outro): por margem, mínima e máxima em %; por
  valor, preço mínimo e máximo em R$ (oferta abaixo do valor mínimo não serve; nas de faixa o preço fica até o valor
  máximo; a margem mínima geral não vale nesse modo).
- **Margem mínima:** a do anúncio ou, sem ela, a geral de Configurações (`companies.min_margin_pct`). Oferta abaixo
  dela não serve. **Margem máxima** (opcional): a do anúncio ou, sem ela, a geral de Configurações
  (`companies.max_margin_pct`, "Margem máxima nas promoções"); sem nenhuma, não há teto.
- **Melhor oferta:** a de maior margem entre as que servem. Empate: a promoção atual (ajustar o preço dela), depois o
  desconto próprio, depois a que termina mais tarde. A promoção ativa entra como está hoje e, se for de faixa,
  também no preço da regra ("ajustar o preço da atual").
- **Fora da escolha:** cupom (`SELLER_COUPON_CAMPAIGN`) e desconto no Pix (`BANK`), que somam no checkout, e anúncio
  sem custo.
- **Aplicar ao SKU:** grava os mesmos limites nos outros anúncios do mesmo SKU (`Painel::PromotionSettings`).
- **Aplicar às variações:** grava também nos anúncios das outras variações do produto (SKUs com o mesmo produto pai
  no Olist, `olist_products.parent_olist_id`).
- **Regras específicas do anúncio** (`rules_note`, texto livre até 2.000 caracteres): guardadas com os limites, mostradas
  na lista ("com regra própria") e no painel; a rotina das 03:00 vai lê-las.
- Mudar margens: só administradores.

## Aplicar no Mercado Livre (`Painel::PromotionActions`)
- Antes de agir, relê as ofertas do anúncio; só aplica oferta que serve pela regra de margem.
- **Entrar:** `POST /seller-promotions/items/{id}?app_version=v2` com `promotion_id`, `promotion_type` e `deal_price` (faixa)
  ou `offer_id` (preço dado pelo ML: SMART, PRICE_MATCHING…); desconto próprio (`PRICE_DISCOUNT`) por 30 dias.
- **Sair:** `DELETE /seller-promotions/items/{id}?promotion_type=…&promotion_id=…` (ou `offer_id`).
- **Trocar** = sair da atual e entrar na nova; **ajustar o preço** = sair e entrar de novo na mesma. Se a entrada falhar
  depois de sair, tenta voltar para a anterior com o preço de antes e avisa se não conseguiu.
- Escrita sem retentativa automática (`Ml::Client#write`), para não aplicar duas vezes. Relâmpago e oferta do dia (pedem
  estoque reservado) não são aplicados pelo Lunna.
- Histórico em `ml_promotion_actions` (tipo, origem, de/para, preço, margem, ganho, ok/erro, usuário).

## Dados e atualização
- `Ml::Sync::Promotions`, dentro da sincronização do ML, a cada **1 hora** (`PROMOTIONS_EVERY`): promoções da conta
  (`/seller-promotions/users/{id}`) e ofertas de cada anúncio ativo (`/seller-promotions/items/{id}`, 3 em paralelo,
  cerca de 2 minutos para 300 anúncios). Anúncio com erro mantém as ofertas anteriores. O botão "Atualizar do
  Mercado Livre agora" (administrador) roda `Ml::PromotionsSyncJob`.
- A Central responde 409 ("internal capacity constraints") sob carga; `Ml::Client` tenta de novo em leitura.
- Tabelas: `ml_promotions`, `ml_promotion_offers` (uma linha por anúncio e oferta, trocadas a cada leitura),
  `ml_promotion_settings`; `ml_accounts.promotions_synced_at`.

## Arquivos
**Front (`lunna-web-radar`)**
- `app/pages/promocoes.vue`, `app/components/promocoes/PromotionItemPanel.vue`
- `app/composables/usePromotions.ts`, `app/lib/promotionsClient.ts`, `app/types/promotions.ts`

**API (`lunna-api`)**
- `app/controllers/promotions_controller.rb` (`GET /api/promotions`, `GET /api/promotions/items/:item_id`,
  `PATCH /api/promotions/items/:item_id/settings`, `GET /api/promotions/export`, `POST /api/promotions/sync`)
- `app/services/painel/promotions_query.rb`, `promotion_evaluator.rb`, `promotion_settings.rb`, `promotion_actions.rb`
- `app/services/ml/sync/promotions.rb`, `app/jobs/ml/promotions_sync_job.rb`, `promotions_apply_job.rb`; cliente em
  `app/services/ml/client.rb` (`join_promotion`, `leave_promotion`)
- Rotas novas: `POST /api/promotions/items/:item_id/apply`, `POST .../leave`, `POST /api/promotions/apply_best`,
  `GET /api/promotions/actions`
- Migrations `20261027150001_create_ml_promotions.rb`, `20261027160001_add_max_margin_to_companies.rb`,
  `20261027160002_create_ml_promotion_actions.rb`

## Pendências
- Fase 2 testada no ML real em 2026-10-27 (2 trocas feitas pela tela). Exige o app do ML com permissão de **leitura e
  escrita em Ofertas/Promoções** (DevCenter); só leitura dá 403 do PolicyAgent, e a tela avisa.
- Fase 3: rotina das 03:00 (recadastrar promoção que acabou ou caiu e trocar por oferta melhor), primeiro em simulação.
- Redução de tarifa do PRICE_MATCHING: confirmar como o ML informa; hoje a conta usa a tarifa de `listing_prices`.
- Ofertas relâmpago pedem estoque mínimo; a escolha ainda não confere o estoque.
- Frete quando a promoção cruza R$ 79: hoje usa o frete do preço cheio.
