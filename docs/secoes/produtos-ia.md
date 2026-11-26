# Produtos › Criar Produto com IA

Pedido do usuário em 26/11/2026. Botão grande azul **Criar Produto com IA** na seção Produtos (só administradores). O
produto é cadastrado **no Lunna** (rascunho próprio) e, depois de pronto, exportado para o ERP (etapa seguinte). O modelo
é neutro de ERP: a estrutura de campos foi tirada do cadastro do Olist (que outros ERPs, como Bling e Upseller, seguem
quase igual), mas sem nomes de campo de um ERP específico. A exportação vai em adaptadores (`Erp::Exporters::*`), com o
resultado em `catalog_products.erp_exports`.

Fora desta página (ficam para a publicação do anúncio): promoção/desconto, tipo de anúncio (Clássico/Premium), envio,
Flex, frete grátis e a publicação no Mercado Livre.

## Tipos

- **Simples** (`simple`): um produto, um SKU.
- **Com variações** (`variations`): até 3 **tipos de variação** combinados (ex.: roupas com Cor e Tamanho; Cor,
  Voltagem, Tamanho, Tom ou outro digitado). Os botões dos tipos que faltam continuam visíveis depois do primeiro
  (corrigido em 26/11/2026: antes só sobrava um campo "Outro eixo"). Os valores são digitados separados por vírgula, a
  tela mostra a conta (ex.: 3 × 4 = 12 variações) e "Montar grade" cria todas as combinações (mantendo SKU/EAN/estoque das linhas que já
  existiam). Cada linha: SKU, EAN, preço, estoque inicial (opcional) e **É kit**.
- **Kit** (`kit`): composição de produtos já existentes (SKU + quantidade), escolhidos dos produtos do ERP sincronizados no
  Lunna (`GET /api/catalog_products/sku_search`; pai de variações fica de fora). Opção **Não tenho / não quero SKUs de
  referência**: segue com as referências livres. O custo somado dos componentes aparece e pode ser usado como custo.

### Variação que é kit (decisão de 26/11/2026)

No Olist há 26 variações que são kits (`olist_products.kind = "K"` com `variation_kind = "V"`), sempre no formato
**item que varia + item fixo**: Base Glow 104/105/109… + Pó Solto em todas (`LS-KIT-BASE-POSOLTO`); Secador SCN-01
127V/220V + Difusor (`LS-SCN01-DIF`). Para não existir um 4º tipo nem repetir o item fixo em cada linha:
- cada linha da grade tem **É kit**; marcada, abre a escolha do **item próprio** daquela variação;
- **Itens em todas as variações-kit** (`common_components`) guarda o item fixo uma vez só;
- a composição de uma variação é comuns + próprios (`CatalogProduct#components_for`); linha sem "É kit" é item único.

## Regras de criação (base: regras das fichas de anúncio do usuário, adaptadas)

Quem preenche o quê:
- **Usuário:** referências (links, texto, fotos), SKU/EAN/preço/estoque das variações, preço, custo, medidas da
  embalagem, garantia, regulatório (Anvisa), observações.
- **IA:** nome, marca, linha, modelo, categoria (caminho completo), condição, formato de venda, títulos, descrição, ficha
  técnica, palavras-chave/SEO, medidas da embalagem só quando estão nas referências e são do próprio produto, e sugestão
  de eixos/valores de variação quando o usuário ainda não criou nenhuma.
- A IA **nunca troca o que já tem valor**: por padrão só preenche o que está vazio; a alternativa dela fica em
  `ai_suggestions.kept` ("Sugestões da IA não aplicadas", com "usar esta"). "Gerar de novo substituindo os textos"
  (`replace: true`) troca os textos da IA, nunca preço, SKU, EAN, estoque ou medidas digitadas.
- **Fiscal** (NCM, CEST, origem ICMS, tipo SPED): a IA só sugere (`ai_suggestions.fiscal`), destacado na aba Fiscal com
  "usar"; o usuário confirma.

Método no prompt (`Catalog::AiDraft`): evidências → diagnóstico → texto → verificação.
- Só entra o que está nas evidências; inferido, incerto ou contraditório vai para **Para conferir** (`ai_review`).
  Nada de deduzir voltagem/material/potência/certificação pela foto, nem "profissional/original/premium" sem suporte,
  marcas de concorrentes, depoimentos.
- Títulos: 4, distintos (o ML inativa duplicados), até 60 caracteres; os maiores são descartados e avisados.
- Descrição: texto simples, sem links/contatos/emojis/HTML (limpos também no servidor), seções em MAIÚSCULAS
  (apresentação, diferenciais, modo de uso, conteúdo da embalagem, especificações, precauções, composição).
- Kit: atributo de um componente fica com ele (a cor do acessório não é a do produto principal). A embalagem do kit
  nunca vem de um componente (26/11/2026: a IA usou a caixa do difusor como a do kit secador + difusor): fica em branco,
  com aviso, para o usuário informar.
- EAN: dígito verificador validado (API e tela) e diferente entre variações; SKU diferente entre variações; o kit não
  pode conter o próprio SKU.

Evidências (`Catalog::Evidence`): texto e observações do usuário; links (anúncio do ML lido pela API: título,
atributos, descrição; outros sites pelo texto da página, até 12 mil caracteres, só endereços públicos); SKUs de
referência (cadastro do ERP + anúncio do ML do mesmo SKU, com os atributos com valor lidos na hora); fotos anexadas (até 6,
vão para o modelo de visão).

### Ajustes de 26/11/2026 (pedido do usuário)

- **Custo** é opcional, com o aviso "O custo será atualizado pelo valor de custo informado no lançamento do seu
  estoque, pelo método PEPS (Primeiro que entra, primeira que sai)".
- Abaixo do texto das Referências: sugestão de colar ficha técnica, descrição, perguntas e respostas e avaliações dos
  anúncios usados como referência.
- Fotos de referência também por **colar (Ctrl+V)** um print ou imagem copiada (área "Clique aqui e cole"), além do
  upload de arquivo.
- **Planilha das variações**: "Baixar modelo de planilha" gera um CSV (`;`, UTF-8 com BOM, abre em colunas no Excel)
  com uma coluna por eixo e as variações da grade já preenchidas (se a grade estiver vazia, é montada com os valores
  digitados), mais SKU, EAN, Preço e Estoque inicial. "Enviar planilha preenchida" lê o CSV (`;` ou `,`, com aspas),
  casa as linhas pelos valores dos eixos (sem diferenciar maiúsculas/acentos), preenche SKU/EAN/preço/estoque, cria a
  variação quando a combinação é nova e aponta EAN inválido e colunas faltando (`importVariationsSheet`). Preço aceita
  "129,90" e "1.299,90".

## Status

`rascunho` → `em_revisao` (depois do rascunho da IA) → `pronto` ("Marcar como pronto", bloqueado com EAN inválido ou
título acima de 60). Estoque inicial é opcional; sem ele, o estoque entra depois pela seção Estoque.

## Próximas etapas

1. Imagens: galeria por variação com o gerador de fotos que já existe (aprovar/reprovar, ordem, custo em R$, "+ Adicionar
   foto"), seguindo a jornada de 10 imagens (capa em fundo branco, contexto, diferencial, medidas reais, uso, detalhe,
   benefício, o que acompanha, dúvidas, decisão).
2. Exportar para o ERP: adaptador do Olist (`POST /produtos` da API v3: conferir o que aceita para variações, kit,
   imagens e ficha, e a permissão de escrita em Produtos do aplicativo).

## API

- `GET/POST /api/catalog_products`, `GET/PATCH/DELETE /api/catalog_products/:id` (escrita: admin).
- `POST /api/catalog_products/:id/generate` (`replace`), `POST /api/catalog_products/:id/assets` (data URL),
  `GET/DELETE /api/catalog_product_assets/:id`, `GET /api/catalog_products/sku_search?q=`.

## Arquivos

**Front (`lunna-web`)**
- `app/pages/produtos/index.vue` (botão e lista "Criados no Lunna"), `app/pages/produtos/ia/[id].vue`
- `app/components/produtos/CatalogProductEditor.vue`, `SkuPicker.vue`; `app/lib/catalogProducts.ts`

**API (`lunna-api`)**
- `app/models/catalog_product.rb`, `catalog_product_asset.rb`; `db/migrate/20261126230000_create_catalog_products.rb`
- `app/services/catalog/evidence.rb`, `ai_draft.rb`; `app/controllers/catalog_products_controller.rb`
