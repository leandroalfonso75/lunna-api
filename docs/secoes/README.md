# Seções do Lunna

Cada item do menu lateral do Lunna tem um documento aqui, com o que a seção faz, de onde vêm os dados, as regras de
negócio e os arquivos envolvidos (no front, `lunna-web`, e na API, `lunna-api`). Antes de mexer em uma seção, leia o
documento dela; ao mudar uma regra, atualize o documento no mesmo commit.

| Menu | Documento | Resumo |
|---|---|---|
| Visão geral | [visao-geral.md](visao-geral.md) | Números do dia, alertas e vendas recentes da conta do Mercado Livre |
| Produtos | [produtos.md](produtos.md) | Produtos do Olist ERP: preços, custo (PEPS e kits), estoque Olist + Full |
| Anúncios | [anuncios.md](anuncios.md) | Tabela de anúncios do Mercado Livre com lucro líquido por unidade |
| Vendas | [vendas.md](vendas.md) | Vendas dos últimos 3 meses do Mercado Livre, com envio, pagamento e lucro por venda |
| Ads | [ads.md](ads.md) | Campanhas e anúncios de publicidade (Product Ads) dos últimos 3 meses, com ACOS, ROAS e investimento |
| Curva ABC | [curva-abc.md](curva-abc.md) | Classificação dos anúncios por faturamento, margem e plano com IA |
| Radar Mercado Livre | [radar-ml.md](radar-ml.md) | Consulta de anúncios coletados do Mercado Livre, com histórico de pesquisas |
| Configurações | [configuracoes.md](configuracoes.md) | Empresa, impostos e margem, usuários e contas do Mercado Livre |

## De onde vêm os dados

- **Mercado Livre:** `Ml::Sync::*` lê a conta a cada 5 minutos (anúncios, pedidos, visitas, qualidade, tarifas, frete e
  estoque Full) e grava no banco do Lunna. Somente leitura.
- **Vendas e envios:** pedidos dos últimos 3 meses e o envio de cada um (frete, rastreio, etapas) vêm da mesma leitura
  do Mercado Livre; o envio é completado 60 pedidos por rodada (ver [vendas.md](vendas.md)).
- **Publicidade (Ads):** campanhas, anúncios em campanha e métricas por dia; leitura completa a cada 3 horas e ontem/hoje
  a cada 30 minutos (ver [ads.md](ads.md)).
- **Olist ERP:** `Olist::SyncProducts` lê produtos, preços e estoque a cada 3 minutos; `Olist::SyncCosts` lê as
  movimentações de estoque (para o custo PEPS). Escrita no Olist (preço e estoque) existe na API, só para
  administradores, com confirmação e registro.
- **Regras de negócio moram na API.** O front só exibe, formata e manda filtros (exceção temporária: os filtros do Radar
  rodam no navegador sobre uma base estática; ver [radar-ml.md](radar-ml.md)).

## Como trabalhamos

- Uma branch por assunto (`feature/...`), commits pequenos em português, pull request quando estiver pronto.
- Nada vai para o GitHub, nem para produção, sem o dono pedir (a branch `feature/anuncios-lucro` já foi enviada, sem pull request).
- Testes da API sempre com `RAILS_ENV=test` (ver `CLAUDE.md`); rodar sem isso cai no banco de desenvolvimento.
- Lucro líquido (Anúncios e Vendas): receita − custo − tarifa − frete − despesas fixas (3%) − imposto (11,3%); custo do Olist
  conforme [produtos.md](produtos.md).
- Segredos (`.env`, tokens) nunca entram nos commits.

Documentos de base: [SPEC.md](../SPEC.md), [DECISOES.md](../DECISOES.md) (prevalece sobre a SPEC) e
[METRICS.md](../METRICS.md).
