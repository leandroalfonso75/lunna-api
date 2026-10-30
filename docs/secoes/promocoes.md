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
- **Percorrer a lista:** no painel do anúncio, "Próximo anúncio →" abre o seguinte da lista (na ordem da tela, entrando
  nos produtos com variações) sem mudar nada; na confirmação de aplicar ou sair, "Confirmar e ir para o próximo" aplica
  e, se o ML aceitou, já abre o seguinte. O cabeçalho da tabela fica fixo ao rolar.
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
- **Aumento do preço final** (`companies.promo_allow_price_increase`, "Permitir o aumento do preço para adesão de nova
  promoção", abaixo dos cards): sem permissão, enquanto a promoção atual estiver valendo, nenhuma oferta pode deixar o
  preço final acima do de hoje (oferta fixa acima não serve; nas de faixa, o preço para no de hoje). Com permissão, pode
  subir, respeitada a margem máxima. Os limites antigos de aumento por faixa (2%/3%/5%/7%) e a regra da casa de cem foram
  retirados em 29/10.
- **Base da margem** (`promo_margin_basis`: `after_ads` | `before_ads`): a margem mínima e a máxima valem sobre o lucro
  pós Ads ou sobre o lucro antes do Ads. Os dois lucros são calculados e mostrados (coluna "Lucro antes do Ads").
- **Alvo do preço** (`promo_price_target`: `min` | `max`): o preço final fica mais perto da margem mínima (a máxima é
  barreira) ou da máxima (a mínima é piso).
- **Oferta relâmpago** (`promo_allow_lightning`, "Autorizar a adesão de Oferta Relâmpago"): sem autorização, a relâmpago
  (`LIGHTNING`, `SMART_LIGHTNING`) não é escolhida; com ela, entra como as demais, dentro dos limites de margem.
- **Para revisar:** anúncio em que nenhuma oferta cabe nas regras e a promoção atual também não (ou não há promoção).
  Nada é aplicado; a guia vermelha "Para revisar" lista cada um com a regra que barrou a atual e as que barraram as
  ofertas (`review` na API), a **melhor oferta barrada** (maior margem entre as que não cabem, com o que faltou) e a
  sugestão do que mudar nos limites para ela caber ("Para caber", com o botão "Usar a sugestão" que preenche o campo).
  No painel, o quadro de custos mostra "Hoje" ao lado da melhor oferta barrada; na lista, ela aparece riscada.
- **Aplicar fora das regras** (só administradores, só em "Para revisar"): o painel tem "Aplicar mesmo assim" (a melhor
  oferta barrada no preço dela) e "Outro valor" (preço final em R$ ou % de desconto sobre o preço cheio, só nas ofertas
  de faixa, com margem e lucro aproximados na tela). A API recebe `force` e `price` em `POST .../apply`; o preço precisa
  ficar na faixa do ML e abaixo do preço cheio, e nem `force` passa o que o ML recusaria (encerrada, preço fixo do ML,
  acima do preço cheio, estoque para reservar). A regra ferida vai para `ml_promotion_actions.forced_reason` e aparece no
  Histórico ("mesmo assim: …"). Levar ao SKU/variações não vale aqui (cada anúncio segue as próprias regras).
- **Validade:** o quadro de custos mostra o período (início até o fim) em "Hoje" e na melhor oferta (ou barrada); a lista
  mostra as datas nas colunas da promoção atual e da melhor oferta, e a tabela de ofertas tem a coluna "Validade". Sem
  data na oferta, vale a da campanha (`ml_promotions`); desconto próprio a criar = 30 dias a partir de quando aplicar;
  relâmpago/oferta do dia candidatos = horário definido pelo ML ao entrar.
- **Limites por margem ou por valor** (`limit_mode`, um desabilita o outro): por margem, mínima e máxima em %; por
  valor, preço mínimo e máximo em R$ (oferta abaixo do valor mínimo não serve; nas de faixa o preço fica até o valor
  máximo; a margem mínima geral não vale nesse modo).
- **Margem mínima:** a do anúncio ou, sem ela, a geral de Configurações (`companies.min_margin_pct`). Oferta abaixo
  dela não serve. **Margem máxima** (opcional): a do anúncio ou, sem ela, a geral de Configurações
  (`companies.max_margin_pct`, "Margem máxima nas promoções"); sem nenhuma, não há teto. Com alvo na mínima, a máxima é
  só uma **barreira**; com alvo na máxima, a mínima é só piso. No relâmpago, o preço não passa do `price` que o ML manda
  na oferta (acima dele o ML recusa com `ERROR_CREDIBILITY_DISCOUNTED_PRICE`).
- **Melhor oferta (desde 29/10):** a margem mais perto do alvo (mínima por padrão), ou seja, a de **menor** margem entre
  as que servem (a de maior, com alvo na máxima). Nas ofertas de faixa, o preço é o mais perto do alvo que respeita o
  piso e o teto. Preferência: primeiro as campanhas do
  Mercado Livre (e a promoção atual); o desconto próprio (`PRICE_DISCOUNT`, que o Lunna cria sem nome) só quando
  nenhuma delas cabe. Campanha do vendedor (`SELLER_CAMPAIGN`, criada com nome na Central) não é escolhida para entrar,
  só pela tela; o Lunna nunca cria campanha com nome. Empate: a promoção atual, depois
  o desconto próprio, depois a que termina mais tarde. A promoção ativa entra como está hoje e, se for de faixa, também
  no preço da regra ("ajustar o preço da atual").
- **Trava de lucro:** quando a situação de hoje está dentro dos limites (a promoção atual ou, sem promoção, o preço do
  anúncio), nenhuma oferta que reduza o lucro por unidade serve ("reduziria o lucro de R$ x para R$ y"). Com "Permitir
  reduzir o preço mesmo com redução da margem" (abaixo dos cards; `companies.promo_allow_margin_drop` e
  `promo_margin_drop_tolerance`, em pontos percentuais), a margem pode cair até a tolerância. Fora dos limites (abaixo
  da mínima ou acima da máxima) não há trava: a regra manda mudar, e o preço vai para a margem mais perto da mínima.
- **Começo da oferta:** só troca na hora se a nova já começou. Se a atual está valendo e a melhor começa depois, o
  anúncio continua na atual, entra na nova (`agendar`) e, se a atual ainda vale quando a nova começa, sai dela nessa
  hora (`Ml::PromotionsHandoffJob`, 5 minutos depois do início). Início = o da oferta ou, sem ele, o da campanha. Em empate de
  margem, a que já começou vence a que começa depois. Promoção programada (`pending`, o anúncio já entrou e ela ainda não
  começou) não conta como a atual nem é escolhida de novo; se o anúncio entra numa promoção tendo uma programada, sai
  desta quando a programada começar (cobre o intervalo entre o fim da atual e o início da programada).
- **Fora da escolha:** cupom (`SELLER_COUPON_CAMPAIGN`) e desconto no Pix (`BANK`), que somam no checkout, e anúncio
  sem custo.
- **Aplicar ao SKU:** grava os mesmos limites nos outros anúncios do mesmo SKU (`Painel::PromotionSettings`).
- **Aplicar às variações:** grava também nos anúncios das outras variações do produto (SKUs com o mesmo produto pai
  no Olist, `olist_products.parent_olist_id`).
- **Regras específicas do anúncio** (`rules_note`, texto livre até 2.000 caracteres): guardadas com os limites, mostradas
  na lista ("com regra própria") e no painel; a rotina das 03:00 vai lê-las.
- Mudar margens: só administradores.

## Aplicar no Mercado Livre (`Painel::PromotionActions`)
- Antes de agir, relê as ofertas do anúncio; só aplica oferta que serve pelas regras, salvo "aplicar mesmo assim" (acima).
- **Entrar:** `POST /seller-promotions/items/{id}?app_version=v2` com `promotion_id`, `promotion_type` e `deal_price` (faixa)
  ou `offer_id` (preço dado pelo ML: SMART, PRICE_MATCHING…); desconto próprio (`PRICE_DISCOUNT`) por 30 dias.
- **Sair:** `DELETE /seller-promotions/items/{id}?promotion_type=…&promotion_id=…` (ou `offer_id`).
- **Trocar** = sair da atual e entrar na nova; **ajustar o preço** = sair e entrar de novo na mesma. Se a entrada falhar
  depois de sair, tenta voltar para a anterior com o preço de antes e avisa se não conseguiu.
- Escrita sem retentativa automática (`Ml::Client#write`), para não aplicar duas vezes. Relâmpago e oferta do dia (pedem
  estoque reservado) entram com o estoque mínimo que o ML sugere (`stock`), se o anúncio tiver esse estoque.
- Histórico em `ml_promotion_actions` (tipo, origem, de/para, preço, margem, ganho, ok/erro, usuário).

## Não automatizar promoções
- No painel do anúncio (ou do produto), "Não automatizar promoções neste anúncio" (`ml_promotion_settings.automation_enabled
  = false`), com opção de levar às outras variações e aos outros anúncios do mesmo SKU (`PATCH .../automation`; só esse
  campo muda, os limites de cada anúncio ficam).
- Anúncio não automatizado: a rotina das 03:00 não mexe (registra a melhor oferta como sugestão), o lote e "levar ao
  produto" pulam. Só muda pela tela, um a um. Aparece com a marca "não automatizado" e na guia "Não automatizados".

## Catálogo
- A lista mostra em verde "Catálogo · com/sem sincronização" (anúncio de catálogo; sincronizado = ligado a um
  tradicional, `ml_items.item_relations`) e "Sincronizado com catálogo" no tradicional ligado. Mostra também Clássico ou
  Premium e as vendas (30 dias e total).
- **Filtro Catálogo** (guia "Catálogo", com "N perdendo"): só os anúncios de catálogo, com "Ganhando", "Dividindo o 1º
  lugar" ou "Perdendo" (lido de `/items/{id}/price_to_win` a cada 30 minutos em `Ml::Sync::CatalogStatus`, também na
  leitura manual e no início da rotina; campos `ml_items.catalog_*`). Perdendo: o preço para ganhar, quanto reduzir e a
  sugestão de promoção que chega nele (as de faixa no próprio preço alvo, as fixas já abaixo dele; prefere a que cabe nas
  regras, depois a de maior lucro), com margem e a regra que fere.
- **Incluir anúncios de catálogo na automatização** (abaixo dos cards; `companies.promo_include_catalog`). Desligado
  (padrão): a rotina e o lote não mexem em anúncio de catálogo (`catalogo_fora`). Ligado: perdendo, a rotina aplica a
  sugestão no preço para ganhar se ela couber nas regras; depois de uma mudança, uma
  hora depois `Painel::CatalogCheck` confere no ML (`/items/{id}/price_to_win`) se está ganhando (`winning` ou
  `sharing_first_place`). Se não, volta ao preço anterior (a promoção de antes no preço de antes, com "aplicar mesmo
  assim", ou sai da promoção) e confere de novo depois de uma hora; sem ganhar ainda, fica em `ml_catalog_checks` como
  `analise_manual` e aparece no aviso "Catálogo para análise manual" da tela (com "Marcar como visto").

## Rotina automática (`Painel::PromotionRoutine`, `Ml::PromotionsRoutineJob`)
- **O que a rotina verifica (definido pelo usuário em 29/10):** só (1) anúncio que ficou sem promoção (acabou ou caiu):
  entra na melhor oferta que já começou (campanha do ML ou, se nenhuma couber, desconto próprio sem nome); e (2) campanha
  do ML mais atraente que a atual: troca, ou, se começa depois, entra nela e mantém a atual até lá. Não ajusta o preço da
  promoção atual, não troca por desconto próprio nem por campanha do vendedor, e não mexe em anúncio com promoção
  programada (`pending`): o intervalo entre o fim da atual e o início da programada é coberto na própria rotina do dia
  em que a atual acabar. Ajustes finos ficam para a tela e o lote.
- `config/recurring.yml` dispara o job a cada hora cheia (`0 * * * * America/Sao_Paulo`); o job roda para cada conta
  ativa cuja empresa ligou a rotina e escolheu aquela hora e aquele dia da semana (`companies.promo_routine_enabled`,
  `promo_routine_mode`, `promo_schedule_hour` 0–23, `promo_schedule_days` 0 = domingo … 6 = sábado; `Company#promo_due?`).
  Tudo isso muda na tela de Promoções, abaixo dos cards (liga/desliga, Simulação/Aplicação real, horário e dias, com
  "Todos os dias"); saiu de Configurações em 29/10.
- **Simulação** (`simulation`): relê a Central, calcula a melhor oferta de cada anúncio com as mesmas regras da tela e
  só registra o que faria. **Aplicação real** (`apply`): aplica pela mesma `Painel::PromotionActions` da tela.
- Age em: trocar, sem promoção (inclui promoção que acabou ou caiu), acima da máxima e abaixo da mínima com oferta que
  serve. Não mexe em: na melhor, sem custo, para revisar (registra a regra), automação desligada e **anúncio com regra
  própria em texto** (a rotina não interpreta texto; registra o motivo).
- Relâmpago e oferta do dia entram reservando o estoque que o ML sugere (`stock.min` da oferta); só servem se o anúncio
  tiver esse estoque disponível.
- Cada execução fica em `ml_promotion_runs` (modo, origem, totais) e cada anúncio em `ml_promotion_actions` (`run_id`,
  antes e depois: preço, margem, lucro). Aba "Rotina automática" em Promoções: lista as execuções, mostra o antes e o
  depois e exporta CSV; "Simular agora" (administrador) roda uma simulação na hora.
- Precisa do Lunna ligado no horário escolhido (computador com Docker, ou servidor).

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
- Rotina das 03:00: ligada em 2026-10-28 em simulação; passar para aplicação real depois de conferir os relatórios.
- Redução de tarifa do PRICE_MATCHING: confirmar como o ML informa; hoje a conta usa a tarifa de `listing_prices`.
- Ofertas relâmpago pedem estoque mínimo; a escolha ainda não confere o estoque.
- Frete quando a promoção cruza R$ 79: hoje usa o frete do preço cheio.
