# Curva ABC (pedido do usuário em 14/11/2026): anúncios cuja descrição já foi feita com IA (Claude), pela página
# "Fichas de Anúncio LUNNA", não recebem sugestões de descrição. Marca as sugestões de descrição como "feita" (sem prazo)
# nos anúncios informados e nas variações da mesma família (cada variação é um anúncio no modelo User Products) cujo SKU
# está entre os SKUs da ficha: a família do ML pode juntar anúncios antigos de outros tons, que não foram feitos pela IA.
# Uso: bin/rails "abc:descricao_ia[MLB1 MLB2,SKU-1 SKU-2]"  (MLBs e SKUs das variações da ficha; rodar ao publicar uma ficha)
namespace :abc do
  desc "Marca anúncios com descrição feita pela IA (sem sugestões de descrição)"
  task :descricao_ia, [ :items, :skus ] => :environment do |_, args|
    ids = args[:items].to_s.split(/[\s;]+/).map(&:strip).reject(&:blank?)
    skus = args[:skus].to_s.split(/[\s;]+/).map(&:strip).reject(&:blank?)
    abort "Informe os MLBs e os SKUs: bin/rails \"abc:descricao_ia[MLB1 MLB2,SKU-1 SKU-2]\"" if ids.empty? || skus.empty?

    MlAccount.find_each do |account|
      items = account.ml_items.where(item_id: ids)
      families = items.where.not(family_id: [ nil, "" ]).distinct.pluck(:family_id)
      all = (items.pluck(:item_id) + account.ml_items.where(family_id: families, sku: skus).pluck(:item_id)).uniq
      next if all.empty?

      all.each { |id| AbcSuggestionAck.done!(account, id, Ml::ItemDescription::KEYS) }
      puts "#{account.nickname || account.id}: #{all.size} anúncio(s) marcados (#{(ids & items.pluck(:item_id)).size} informados + variações)"
    end
  end
end
