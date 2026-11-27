---
name: secao-produtos-ia
description: Use ao alterar, corrigir ou investigar o "Criar Produto com IA" do Lunna (cadastro de produto no Lunna, tipos simples/variações/kit, kit de produto com variações + simples, rascunho pela IA, planilha das variações, exportar para o ERP).
---

1. Leia `docs/secoes/produtos-ia.md` (tipos, regras de criação, decisões de 26 e 27/11/2026, arquivos).
2. Código: `app/models/catalog_product.rb`, `app/services/catalog/` (`evidence.rb`, `ai_draft.rb`, `kit_parts.rb`), `catalog_products_controller.rb`; front `app/pages/produtos/ia/[id].vue`, `components/produtos/CatalogProductEditor.vue`, `KitVariationsCard.vue`, `SkuPicker.vue`, `lib/catalogProducts.ts` (repositório `lunna-web-radar`).
3. O modelo é neutro de ERP: nada de nomes de campo do Olist em `catalog_products`; exportação por adaptador (`Erp::Exporters::*`, etapa 3).
4. Regras de criação (base: skill de fichas de anúncio do usuário, adaptada; não copiar nem alterar a skill): só evidências; o que falta vai para "Para conferir"; títulos até 60 e distintos; descrição sem links/contatos/emojis; fiscal só sugestão; a IA nunca troca o que o usuário preencheu (`ai_suggestions.kept`); embalagem do kit nunca de um componente; atributo de um componente fica com ele.
5. Nada da Lunna Shop fixo (sistema multi-conta): sem sugestão de SKU; preço sugerido = soma do preço cheio dos componentes × quantidade.
6. Kit com variações = grade de variações com cada linha `kit: true` (componente = variação do pai) + o simples em `common_components`.
7. Teste com rascunho próprio e apague só ele pelo ID exato; o resto é do usuário. Nada é criado no Olist nem no ML sem o usuário clicar.
8. Mudou regra ou arquivo? Atualize `docs/secoes/produtos-ia.md` no mesmo commit; testes: `spec/requests/catalog_products_spec.rb` e, no front, `CatalogProductEditor.test.ts` e `lib/catalogProducts.test.ts`.
9. Pendente: etapa 2 (imagens por variação com o gerador de fotos) e etapa 3 (exportar para o ERP: conferir `POST /produtos` da API v3 do Olist e a permissão de escrita em Produtos).
