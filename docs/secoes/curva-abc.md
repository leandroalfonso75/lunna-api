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
  (`Painel::VariationCost`), como em Promoções. Ainda **não** usa as despesas operacionais (diferença para Anúncios).
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
  **Ordem e capa** (pedido do usuário em 04/11/2026): antes de publicar, a janela mostra a galeria final do anúncio de
  destino (fotos atuais + aprovadas) com setas e "Tornar capa"; a 1ª é a capa. A publicação manda `order` (`ml:<id>` /
  `new:<id>`); foto atual fora da lista entra no fim, gerada fora dela não sobe. Ao trocar a capa, `Ai::CoverCheck`
  (`POST /api/photo_jobs/:id/check_cover`, modelo de visão `google/gemini-2.5-flash`, ~US$ 0,001) confere fundo branco,
  texto, logo/marca d'água, borda, produto inteiro, colagem e nitidez; fora do padrão abre o aviso "Capa fora dos padrões
  do Mercado Livre" com **Publicar mesmo assim** (publica direto) e **Cancelar** (volta a ordem de antes).
  **Arrastar, R$ e Reprovar** (pedido do usuário em 25/11/2026; a mesma janela serve Curva ABC e Anúncios › Editar
  anúncios selecionados): as fotos da galeria final também mudam de lugar arrastando (soltar na posição de outra; mexer
  na capa confere a nova). Custos em R$: a API manda `cost_brl` (pedido e cada imagem) e `usd_brl`, pela cotação de
  venda do dólar da AwesomeAPI (`Fx::UsdBrl`, guardada 6 h; sem cotação, a tela mostra US$); o valor em US$ e a
  cotação ficam no título. **Reprovar** ao lado de Aprovar abre o aviso "A reprovação da imagem não exime do pagamento
  de sua geração" com **Excluir mesmo assim** (`DELETE /api/photo_images/:id`, admin: marca `rejected_at`, tira da
  tela, da ordem e da publicação; o custo segue no total do pedido) e **Manter imagem e Aprovar**.

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
- Usar as despesas operacionais, para ficar coerente com Anúncios.
- Fotos: o primeiro envio real confirma se o app do Lunna pode alterar fotos do anúncio (anúncio de catálogo pode recusar).

## Título, ficha técnica e "Ciente" (07/11/2026)

- **Regra do título (documentação do ML, conferida em 07/11/2026):** anúncio de catálogo não troca título; no modelo
  User Products o título é montado pelo ML a partir do `family_name`, que só pode ser alterado se nenhum anúncio do mesmo
  user product tiver venda; no modelo antigo, só com `sold_quantity = 0`. `Ml::TitleRule` decide; sem poder trocar, as
  sugestões de título (e a de termos proibidos) não aparecem.
- **Alterar título AGORA** (`AbcTitleEditor.vue`): título atual, campo de até 60 caracteres (ou o `max_title_length` da
  categoria), "Sugerir títulos" (5 pela IA, `Ai::TitleSuggestions`, sem variação no nome da família) e "Publicar título"
  (`Ml::ItemTitle`: PUT /items/{id} com `family_name` ou `title`; admin, confirmação, `ml_item_edits`).
- **Alterar ficha técnica AGORA** (`AbcSpecsEditor.vue`): campos obrigatórios e principais que faltam (`Ml::ItemSpecs`),
  "Sugerir características" (`Ai::SpecSuggestions`: só valores da lista permitida, só o que dá para afirmar) e
  "Publicar alterações" (PUT /items/{id} com `attributes`; admin, confirmação, `ml_item_edits`).
- **Ciente** em Vídeo, Tipo de anúncio e Qualidade (`abc_suggestion_acks`): "aplicada no ML" esconde por 30 dias,
  "aguardar" por 15; depois, se ainda valer, a sugestão volta.
- IA de texto: `Ai::JsonChat` com o modelo da empresa ou, sem ele, `google/gemini-2.5-flash` (só precisa da chave).
- Rotas: GET/POST `/api/items/:id/title`, POST `/title/suggest`, GET/POST `/api/items/:id/specs`, POST `/specs/suggest`,
  POST `/api/items/:id/suggestion_acks`.

## Atualizações de 07–09/11/2026

- **Preço e frete:** todo cenário a partir de R$ 79 usa o frete grátis obrigatório pela tabela do ML por faixa
  (`ml_items.ship_cost_tiers`: 79, 100, 120, 150, 200, lidos em todo anúncio pela sincronização de detalhes). Cada cenário
  (menos "Hoje") tem **Aplicar novo preço sugerido** (`POST /api/items/:id/price`, `Ml::ItemPrice`: admin, confirmação,
  registro em `ml_item_edits`, trava de 60%); no cenário "Com frete grátis" no mesmo preço, aplicar liga o frete grátis.
  Campo **Simular outro preço** com a mesma conta (`calculator` na sugestão).
- **Ficha técnica:** "Não se aplica" (value_id -1) nos campos não obrigatórios; números de documentos regulatórios (Anvisa,
  CONAMA, AFE, INMETRO) não obrigatórios ficam fora (`Ml::SpecRules`); campo multivalorado vai separado por vírgula.
- **Catálogo:** sem sugestões de título, fotos, descrição e ficha técnica (vêm do produto do catálogo).
- **Vídeo:** o vídeo atual do ML (clip) não vem em `video_id`; vale a regra HAS_SHORTS da qualidade (`ml_items.has_clip`).
  Sugestão de vídeo só quando o ML confirma que falta.
- **Filtro** por produto (Olist), SKU, MLB ou palavra-chave, valendo em todas as abas (`skus`/`products` nas linhas).
- **Avaliar aumento de preço:** preço abaixo da referência do ML — espaço para ganhar margem, não para exposição.

## Atualizações de 10/11/2026

- **Preço em maturação:** depois de aplicar um preço sugerido ou clicar "Não aplicar nenhum preço sugerido", o anúncio
  fica 15 dias sem sugestões de preço e frete (ack "preço:*", `AbcSuggestionAck.hold_price!`); a tela mostra o aviso.
- **Ciente por padrão:** toda sugestão sem botão próprio ganha os botões Ciente (inclusive tipos futuros); só preço, frete
  e dados ficam de fora (`NO_CIENTE_AREAS`). Estoque e Logística já têm.
- **Ficha técnica incompleta** (obrigatória ou principal) é sempre **Urgente**.

## Ficha técnica em anúncio com variações (11/11/2026)

- Erro 400 `item.attributes.invalid` no MLB2729901870 (variações Preto 127V / Preto 220V): o Lunna pedia de novo Cor e
  Voltagem (já estão nas combinações das variações) e mandava tudo no anúncio. Agora `Ml::ItemSpecs` conta as combinações
  e os atributos das variações como preenchidos; atributo com tag `variation_attribute` vai em cada variação
  (`per_variation: "same"`, mesmo valor para todas), e o GTIN tem um campo por variação (`"each"`). O PUT manda todas
  as variações (a que fica de fora o ML apaga), com os atributos que já tinham.
- Recusa do ML mostra só as mensagens de `cause` (`ItemSpecs.ml_reason`); o erro completo fica em `ml_item_edits.error`.

## Aplicar às variações do mesmo anúncio pai (13/11/2026)

- Variações = anúncios da mesma família do ML (`ml_items.family_id`, lido no multiget), mesmo tipo (Clássico/Premium) e
  fora do catálogo (`Ml::ItemVariations`). Outro anúncio do mesmo produto não entra. `GET /api/items/:id/variations`.
- **Ciente** (inclusive "Não aplicar nenhum preço sugerido"): com variações, a tela pergunta "Sim, em todas as variações" ou
  "Só neste anúncio" (`apply_to_variations`).
- **Ficha técnica:** opção "Aplicar também às outras variações": em cada uma publica só os campos comuns que faltam nela
  (`ItemSpecs.publish_shared`); atributos de variação (cor, tom, voltagem, GTIN, SKU; tags `allow_variations`,
  `variation_attribute`, `defines_picture`) nunca são copiados.
- **Preço sugerido:** opção "e nas outras N variações": o mesmo preço (e frete grátis) em cada uma, com a mesma trava de
  60% e os 15 dias de maturação; a que já está no preço conta como feita. Cada escrita fica em `ml_item_edits`.

## Sugestões revistas (14/11/2026)

- **Saíram** (o próprio Mercado Livre já sugere): "Testar anúncio Premium", "Adicionar vídeo" e as recomendações de
  qualidade do ML (vídeo, parcelamento sem juros etc.). Regras removidas do motor (`Abc::SuggestionEngine`).
- **Modelo com palavras-chave** (`rule_model_keywords`, prioridade 2, área "busca"): fora do catálogo, com detalhes
  carregados, quando o campo Modelo tem menos de 60 caracteres. O ML aceita até 110 caracteres no Modelo e usa o texto na
  busca: em vez do código do produto vão as palavras mais buscadas (ML e Google), de preferência as que não estão no
  título; o modelo real vai em "Modelo detalhado" (DETAILED_MODEL). Botão "Alterar modelo AGORA" (`AbcModelEditor.vue`):
  mostra as mais buscadas da categoria (`GET /trends/MLB/{categoria}`), "Sugerir palavras-chave" (IA, 3 opções, sem marcas
  de terceiros nem termos promocionais, cortadas sem quebrar palavra) e publica MODEL no anúncio e DETAILED_MODEL no
  anúncio ou em cada variação (atributo de variação). Serviços: `Ml::ItemModelKeywords`, `Ai::ModelKeywordSuggestions`.
  Rotas: `GET/POST /api/items/:id/model`, `POST /api/items/:id/model/suggest`.
- **Descrição mais chamativa** (`rule_description_boost`, prioridade 3): curvas A/B com descrição de 400+ caracteres. As
  regras "Escrever descrição" e "Ampliar descrição" também ganharam o botão "Alterar descrição AGORA"
  (`AbcDescriptionEditor.vue`): a IA reescreve (benefício na abertura, diferenciais em tópicos, uso, especificações, o que
  vem na embalagem e perguntas frequentes a partir das perguntas reais do anúncio), em texto puro; valores em conflito
  entre ficha e descrição viram aviso "Conferir:". Publica com `PUT /items/{id}/description` (recusa links, e-mail e
  telefone) e marca "Deixar a descrição mais chamativa" como aplicada por 30 dias. Serviços: `Ml::ItemDescription`,
  `Ai::DescriptionSuggestion`. Rotas: `GET/POST /api/items/:id/description`, `POST /api/items/:id/description/suggest`.
- As duas escritas: só admin, com confirmação, registradas em `ml_item_edits` (kinds "modelo" e "descricao"), e aceitam
  "aplicar também às outras variações do anúncio pai".

### Ajuste do Modelo com palavras-chave (14/11/2026, pedido do usuário)
- O Modelo recebe as buscas mais feitas da categoria no ML **exatamente como aparecem** (`/trends/MLB/{categoria}`, até 50),
  uma depois da outra, até 110 caracteres. A IA só escolhe quais buscas servem para o produto e marca as que citam outra
  marca; a montagem é feita no código com o texto exato (termo inventado ou alterado pela IA fica de fora).
- Regra: as **duas primeiras** buscas não podem ter marca diferente da do anúncio (num secador Mondial, Gama, Philco e Taiff
  só a partir da terceira). Buscas com a marca do próprio anúncio contam como dele.
- Até 3 montagens: mais ligadas ao produto primeiro, ordem das mais buscadas e só sem outras marcas (iguais são juntadas).
- Modelo detalhado: o modelo real seguido de outros detalhes relevantes do produto (potência, tecnologia, acessórios...).
- Descrição (ajuste de 14/11/2026, regra do usuário): a sugestão NUNCA elimina avisos da descrição atual que evitam
  reclamação (ex.: difusor de outra marca que a do secador, não é bivolt, o que não vem na embalagem, limitações de uso).
  Eles ficam numa seção "INFORMAÇÕES IMPORTANTES" e a tela lista os avisos mantidos para conferência. Caixa de texto 4x
  mais alta.
- Mesmo produto em outros anúncios (14/11/2026, pedido do usuário): ao confirmar a publicação de Modelo ou descrição, se
  houver outros anúncios com o mesmo SKU (fora do catálogo e não encerrados, ex.: Clássico e Premium), o Lunna pergunta
  se a alteração vale também para eles (`AbcSameSkuChoice.vue`, nenhum marcado). `GET /api/items/:id/variations` devolve
  `same_sku`; a publicação aceita `also_item_ids[]` (só ids do mesmo SKU; `Ml::ItemVariations.same_sku`).
- Depois de publicar (14/11/2026, pedido do usuário): Modelo ou descrição publicados pelo Lunna não voltam a ser sugeridos
  naquele anúncio (ack `feita`, sem prazo; também nos anúncios do mesmo SKU/variações onde foi publicado). Botão
  **Ignorar** ao lado de "Alterar modelo/descrição AGORA": nada muda e a sugestão some por 30 dias (ack `ignorar`).
- Descrição feita pela IA (14/11/2026, pedido do usuário): anúncios publicados pela página "Fichas de Anúncio LUNNA"
  (descrição feita com o Claude) não recebem sugestões de descrição. Marcação com
  `bin/rails "abc:descricao_ia[MLBs,SKUs]"` (MLBs dos anúncios e SKUs das variações da ficha; inclui as variações da mesma
  família com SKU da ficha). Rodado em 14/11 para as 7 fichas com MLB: 296 anúncios. Rodar de novo a cada ficha publicada.
