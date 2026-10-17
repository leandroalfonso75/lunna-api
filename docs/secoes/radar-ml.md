# Radar Mercado Livre

Consulta de anúncios do Mercado Livre (de todas as categorias), adaptada do artefato "Radar Beleza ML". É uma consulta
de **mercado** (anúncios de quaisquer vendedores), diferente da tabela de Anúncios, que mostra os seus.

## O que mostra
- Filtros: **categoria (obrigatória)** em cascata (as subcategorias são opcionais e, sem escolher, entram todas as de
  baixo), período de criação do anúncio, catálogo/tradicional, vendedor, marca, preço, receita, vendas e avaliação.
- O resultado só aparece depois de clicar em **Pesquisar**. Ordenação, totais (anúncios, vendas, receita, preço
  mediano) e "Copiar resultado".
- **Pesquisas dos últimos 3 meses:** botão no topo; cada pesquisa fica salva e, ao abrir, reaplica os filtros e permite
  refinar por subcategoria dentro da categoria da pesquisa (sem criar nova entrada).
- **Pedir coleta desta categoria:** registra um pedido na fila; nada é coletado nem agendado.

## Dados (estado atual: protótipo)
- A base é um arquivo estático coletado em 23/09/2026 (só **Beleza e Cuidado Pessoal**, ~39 mil anúncios):
  `public/radar/data.json`. Os períodos são contados a partir da data da coleta.
- As categorias de todo o Mercado Livre vêm da planilha de tarifas: `public/radar/categorias.json` (10.329 caminhos).
  Categorias sem anúncios na base aparecem com (0).
- **Os filtros rodam no navegador** (`app/lib/radar.ts`). Isso foge da regra "regra de negócio só na API" e é temporário;
  quando houver coleta no servidor, vira endpoint.
- Coletar anúncios do Mercado Livre exige um navegador logado no ML (o servidor é redirecionado para verificação de
  conta). **Como e de onde coletar será definido depois do deploy.**

## Arquivos
**Front (`lunna-web`)**
- `app/pages/radar-ml.vue`, `app/lib/radar.ts` (índice, filtros, ordenação, TSV), `radarCollectionsClient.ts`, `radarSearchesClient.ts`
- `app/composables/useRadarCollections.ts`, `useRadarSearches.ts`
- `public/radar/data.json`, `public/radar/categorias.json`

**API (`lunna-api`)**
- `app/controllers/radar_collections_controller.rb` (fila de pedidos de coleta), `radar_searches_controller.rb` (histórico)
- Modelos `radar_collection`, `radar_search`

## Pendências
- Definir a fonte e o jeito da coleta; ligar a fila de pedidos a um coletor.
- Guardar, em cada pesquisa, a qual coleta ela se refere.
