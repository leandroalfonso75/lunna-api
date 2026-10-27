# Promoções

Promoções da **Central de Promoções do Mercado Livre** por anúncio: a promoção atual, a melhor oferta disponível
(maior margem dentro da margem mínima e máxima) e o ganho da troca. Proposta completa e fases:
[Seção Promoções do Lunna: proposta](https://claude.ai/artifact/524x29CDnNHJy2wo7rrwEg).

Fase 1 (pronta): ver, comparar, configurar margens e exportar. **Não mexe no Mercado Livre.** Fase 2 (aderir, editar
preço e sair pelo Lunna) e fase 3 (rotina das 03:00) ainda não existem.

## O que a tela mostra
- **Cartões:** anúncios em promoção, sem promoção, trocas que rendem mais (com o ganho somado por unidade) e abaixo
  da margem mínima.
- **Aba Anúncios:** um anúncio ativo por linha, com preço cheio, promoção atual (preço, margem e lucro por unidade),
  melhor oferta, ganho por unidade e situação: Trocar por melhor, Sem promoção, Abaixo da mínima, Na melhor, Sem custo.
  Filtros por situação, por promoção e busca por anúncio, título ou SKU.
- **Painel do anúncio (clique na linha):** todas as ofertas do anúncio com preço, parte do ML, tarifa e margem (a
  melhor marcada) e o formulário de margem mínima e máxima, com "aplicar aos outros anúncios do SKU".
- **Aba Promoções do ML:** cada promoção da Central com tipo, situação, período, anúncios ativos e candidatos;
  "Ver anúncios" filtra a aba Anúncios por ela.
- **Exportar todas (CSV):** uma linha por anúncio e oferta (ativa ou candidata), com preços, faixa, parte do ML,
  margem e lucro. Separador `;` e vírgula decimal, para abrir direto no Excel.

## Regras
- **Margem da oferta** (`Painel::PromotionEvaluator`):
  lucro = preço + parte do ML − custo − tarifa − frete − imposto − despesas fixas; margem = lucro ÷ preço.
  - Parte do ML: ofertas com desconto dividido (`meli_percentage`) — o ML banca esse % do preço original.
  - Tarifa: a do ML no preço da oferta (`/sites/MLB/listing_prices`, guardada em `ml_promotion_offers.fees`); em outro
    preço, % da tarifa × preço + taxa fixa.
  - Frete, custo, imposto e despesas fixas: os mesmos da seção Anúncios.
- **Preço da oferta:** fixo (SMART, PRICE_MATCHING, relâmpago com ML, DOD) ou, nas de faixa (campanha do vendedor,
  DEAL, desconto próprio, relâmpago), o maior preço permitido. Com margem máxima, desce o preço até ela.
- **Margem mínima:** a do anúncio ou, sem ela, a geral de Configurações (`companies.min_margin_pct`). Oferta abaixo
  dela não serve. Margem máxima é opcional e só por anúncio.
- **Melhor oferta:** a de maior margem entre as que servem. Empate: a promoção atual (ajustar o preço dela), depois o
  desconto próprio, depois a que termina mais tarde. A promoção ativa entra como está hoje e, se for de faixa,
  também no preço da regra ("ajustar o preço da atual").
- **Fora da escolha:** cupom (`SELLER_COUPON_CAMPAIGN`) e desconto no Pix (`BANK`), que somam no checkout, e anúncio
  sem custo.
- **Aplicar ao SKU:** grava as mesmas margens nos outros anúncios do mesmo SKU (`Painel::PromotionSettings`).
- Mudar margens: só administradores.

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
- `app/services/painel/promotions_query.rb`, `promotion_evaluator.rb`, `promotion_settings.rb`
- `app/services/ml/sync/promotions.rb`, `app/jobs/ml/promotions_sync_job.rb`; cliente em `app/services/ml/client.rb`
- Migration `20261027150001_create_ml_promotions.rb`

## Pendências
- Fase 2: aderir, editar preço, sair e criar desconto próprio (POST/DELETE `/seller-promotions/items/{id}`), com
  confirmação e histórico.
- Fase 3: rotina das 03:00 (recadastrar promoção que acabou ou caiu e trocar por oferta melhor), primeiro em simulação.
- Redução de tarifa do PRICE_MATCHING: confirmar como o ML informa; hoje a conta usa a tarifa de `listing_prices`.
- Ofertas relâmpago pedem estoque mínimo; a escolha ainda não confere o estoque.
- Frete quando a promoção cruza R$ 79: hoje usa o frete do preço cheio.
