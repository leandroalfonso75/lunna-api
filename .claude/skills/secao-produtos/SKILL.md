---
name: secao-produtos
description: Use ao alterar, corrigir ou investigar a página Produtos do Lunna (Olist ERP, estoque Olist/Full, custo PEPS, kits, variações, escrita no Olist).
---

1. Leia `docs/secoes/produtos.md` (regras, fluxo de dados, arquivos do front e da API).
2. Código principal: `app/services/olist/`, `app/jobs/olist/`, `olist_products_controller.rb`; no front `app/pages/produtos.vue` (repositório `lunna-web-radar`).
3. Respeite: Olist só com `confirm=true` na escrita; nunca testar escrita no ERP real sem o dono autorizar; segredos fora do git e do chat.
4. Mudou regra ou arquivo? Atualize `docs/secoes/produtos.md` no mesmo commit e rode `bundle exec rspec spec/services/olist`.
