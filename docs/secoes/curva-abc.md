# Curva ABC

Classifica os anúncios por faturamento (A, B, C) e mostra lucro, margem e sugestões.

## O que mostra
- Resumo por curva, abas A/B/C, tabela com lucro e margem por unidade e no mês, e detalhe com **plano de ação com IA**.
- A IA (OpenRouter) usa a chave e o modelo configurados pela empresa em Configurações > Empresa.

## Regras (resumo; base em `docs/SPEC.md` seção 8 e `docs/DECISOES.md`)
- Cortes da curva e margem mínima por empresa (`abc_cut_a`, `abc_cut_b`, `min_margin_pct`).
- Lucro/sobra por unidade e no mês (`Abc::Economics`): preço − tarifa − frete − imposto − custo (custo manual `ml_costs`).
- Preço sugerido e custo máximo (`Abc::PriceSuggestion`), diagnóstico e recomendações (`Abc::SuggestionEngine`).
- Custo: o manual (`ml_costs`) e, sem ele (desde 04/11/2026), o do Olist (`Olist::UnitCost`) e o das variações vendidas
  (`Painel::VariationCost`), como em Promoções. Ainda **não** usa as despesas fixas (diferença para Anúncios).
- **Detalhes das ações** (pedido do usuário em 04/11/2026), em "O que fazer para vender mais":
  - **Exposição:** `steps` com as medidas que valem para o anúncio (Product Ads se não estiver em campanha ativa, título,
    promoções, frete grátis, Full, ficha técnica, qualidade, preço frente à referência).
  - **Preço:** `options` com preço, tarifa (mesma % de hoje), frete, imposto, custo, lucro e margem: referência do ML,
    preço de hoje e os preços para a margem mínima e mínima + 5 p.p. Sem custo: só referência e hoje, "antes do custo".
  - **Frete grátis:** `options` hoje × com frete grátis (`ml_items.ship_cost_free`, lido na sincronização de detalhes
    para quem não oferece frete grátis) × preço que mantém a margem de hoje pagando o frete.
  - **Fotos:** `action: gerar_fotos` abre a janela de geração (abaixo).
- **Descrição:** anúncio de catálogo tem a descrição do anúncio vazia; o ML mostra a do produto do catálogo
  (`/products/{id}` → `short_description`). `Ml::Sync::Details` lê essa quando a do anúncio vem vazia (até 04/11/2026
  53 anúncios apareciam como "sem descrição" por isso).
- **Gerar fotos com IA** (pedido do usuário em 04/11/2026): janela `AbcPhotoGenerator` → escolhe as fotos do próprio
  anúncio como referência (todas marcadas), quantas imagens (1 a 6), instruções e anexos opcionais →
  `POST /api/items/:item_id/photos` cria `ml_photo_jobs` e `Ai::PhotoGenerationJob` gera pela OpenRouter
  (`Ai::PhotoGenerator`, modelo `companies.ai_image_model`, padrão `google/gemini-2.5-flash-image`, chave em
  Configurações › Empresa), uma imagem por chamada com cenas diferentes (fundo branco, em uso, detalhe, ângulo, kit,
  estilo de vida), mantendo o produto idêntico e sem textos. Imagens em `ml_generated_photos` (bytes no banco). O
  usuário aprova (`PATCH /api/photo_images/:id`) e publica (`POST /api/photo_jobs/:id/publish`, admin, `confirm: true`,
  confirmação dupla na tela): `Ml::PicturePublisher` sobe cada aprovada (`/pictures/items/upload`) e regrava as fotos do
  anúncio = as atuais + as novas no fim (limite de 10). Anúncio de **catálogo** não deixa trocar fotos (o ML usa as do produto do
  catálogo; "pictures is not modifiable"): a janela avisa e publica no anúncio **tradicional do mesmo produto**
  (`user_product_id`), escolhido pelo usuário (`target_item_id`; só aceita o próprio ou um tradicional do mesmo produto).
  Imagens que subiram e não foram ligadas ao anúncio (troca recusada) são reaproveitadas na próxima tentativa.
  Custo de cada imagem (US$, `usage.cost` da OpenRouter) fica em `ml_generated_photos.cost_usd`.

## Arquivos
**Front (`lunna-web`)**
- `app/pages/curva-abc.vue`, `app/components/abc/` (`AbcTable`, `AbcDetail`, `AiPlanPanel`, `AbcPhotoGenerator`)
- `app/composables/useAbc.ts`, `useAiPlan.ts`; `app/lib/aiPlanClient.ts`, `aiPlanRunner.ts`

**API (`lunna-api`)**
- `app/controllers/abc_controller.rb`, `ai_plans_controller.rb`, `photo_jobs_controller.rb`
- `app/services/ai/photo_generator.rb`, `app/services/ml/picture_publisher.rb`, `app/jobs/ai/photo_generation_job.rb`,
  modelos `MlPhotoJob` e `MlGeneratedPhoto`
- `app/services/abc/` (`classifier`, `economics`, `params`, `price_suggestion`, `report`, `suggestion_engine`) e `app/services/ai/`
- `app/jobs/ai/` (geração do plano em segundo plano, lida por polling)

## Pendências
- Usar as despesas fixas, para ficar coerente com Anúncios.
- Fotos: o primeiro envio real confirma se o app do Lunna pode alterar fotos do anúncio (anúncio de catálogo pode recusar).
