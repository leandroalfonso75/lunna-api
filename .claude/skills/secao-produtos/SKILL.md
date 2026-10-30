---
name: secao-produtos
description: Use ao alterar, corrigir ou investigar a página Produtos do Lunna (Olist ERP, estoque Olist/Full, custo PEPS, kits, variações, escrita no Olist).
---

1. Leia `docs/secoes/produtos.md` (regras, fluxo de dados, arquivos do front e da API).
2. Código principal: `app/services/olist/`, `app/jobs/olist/`, `olist_products_controller.rb`; no front `app/pages/produtos.vue` (repositório `lunna-web-radar`).
3. Custo: a ordem é PEPS (refeito pelas entradas mais recentes quando o histórico não fecha) → custo cadastrado → custo médio → custo da última entrada. Entrada de estoque já lançada não é editável no Olist (nem pela API): o custo se corrige no cadastro do produto, aba Custos.
4. Respeite: Olist só com `confirm=true` na escrita; nunca testar escrita no ERP real sem o dono autorizar; segredos fora do git e do chat.
5. Mudou regra ou arquivo? Atualize `docs/secoes/produtos.md` no mesmo commit e rode os testes com `RAILS_ENV=test` (ver CLAUDE.md), por exemplo `spec/services/olist`.
6. A lista mostra a foto do anúncio do ML com o mesmo SKU (`thumbnail` em `Olist::ProductPayloads`).
