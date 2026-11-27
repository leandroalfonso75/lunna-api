require "net/http"

# Migração dos produtos do ERP para a ficha completa do Lunna (27/11/2026, aprovada pelo usuário).
#
# Regras do usuário:
# - não exclui nada: cada produto do ERP ganha (ou atualiza) uma ficha presa ao id dele no ERP; a cópia sincronizada
#   (olist_products), o custo PEPS e o histórico de entradas NÃO mudam;
# - o ERP manda nos dados (o Lunna copia); só leitura no ERP;
# - não importa produto inativo/excluído no ERP nem os removidos da lista do Lunna (vão para o relatório);
# - imagens baixadas para o Lunna, na ordem do ERP; variações com eixos; kits com componentes e quantidades.
# Variação pedida sozinha importa o pai (com todas as variações).
module Erp
  class CatalogImport
    Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)
    IMAGE_TIMEOUT = 20
    MIMES = { "image/jpeg" => "image/jpeg", "image/jpg" => "image/jpeg", "image/png" => "image/png", "image/webp" => "image/webp" }.freeze

    def self.call(company, erp_ids:, client: nil, downloader: nil, sleeper: nil)
      new(company, client: client, downloader: downloader, sleeper: sleeper).call(erp_ids)
    end

    # sleeper: pausa entre leituras no ERP (ele limita as chamadas por minuto); nos testes, nenhuma
    def initialize(company, client: nil, downloader: nil, sleeper: nil)
      @company = company
      @sleeper = sleeper || (client ? ->(_) {} : ->(s) { sleep(s) })
      @client = client || Olist::Client.new(company.olist_connection)
      @downloader = downloader || method(:download)
    end

    def call(erp_ids)
      result = Result.new(imported: [], skipped: [], errors: [])
      top_ids(erp_ids, result).each do |id|
        pause
        result.imported << import_one(id)
      rescue StandardError => e
        result.errors << { erp_id: id, error: "#{e.class}: #{e.message}".truncate(300) }
      end
      result
    end

    # Cadastro do ERP de um produto e das variações que precisam ser lidas (kits e imagens próprias).
    def fetch(id)
      payload = @client.product(id)
      children = Array(payload["variacoes"]).to_h { |v| pause; [ v["id"], @client.product(v["id"]) ] }
      [ payload, children ]
    end

    private

    def pause = @sleeper.call(1.0)

    # Resolve variação → pai; tira inativos/excluídos e os removidos da lista do Lunna.
    def top_ids(erp_ids, result)
      mirror = @company.olist_products.where(olist_id: erp_ids).index_by(&:olist_id)
      erp_ids.map(&:to_i).filter_map do |id|
        row = mirror[id]
        top = row&.parent_olist_id || id
        top_row = @company.olist_products.find_by(olist_id: top)
        if top_row && (top_row.status != "A" || top_row.hidden_at)
          result.skipped << { erp_id: top, sku: top_row.sku, reason: top_row.status != "A" ? "inativo/excluído no ERP" : "removido da lista do Lunna" }
          next
        end
        top
      end.uniq
    end

    def import_one(id)
      payload, children = fetch(id)
      mapped = OlistProductMapper.call(payload, children: children)
      product = @company.catalog_products.find_or_initialize_by(erp_key: OlistProductMapper::ERP_KEY, erp_id: payload["id"])
      warnings = mapped[:warnings] + component_warnings(mapped[:attrs])
      product.assign_attributes(mapped[:attrs].merge(erp_synced_at: Time.current, erp_warnings: warnings))
      product.save!
      images = sync_images(product, mapped[:images], warnings)
      product.update_columns(erp_warnings: warnings.uniq) if warnings.size != product.erp_warnings.size
      { erp_id: product.erp_id, id: product.id, sku: product.sku, kind: product.kind, images: images, warnings: warnings.uniq }
    end

    # Componente de kit que não existe (ativo) na cópia do ERP: o estoque do kit fica zero.
    def component_warnings(attrs)
      comps = Array(attrs[:kit_components]) + Array(attrs[:variations]).flat_map { |v| Array(v["components"]) }
      skus = comps.map { |c| c["sku"] }.uniq
      return [] if skus.empty?

      found = @company.olist_products.where(sku: skus, status: "A").pluck(:sku)
      (skus - found).map { |s| "componente #{s} não está ativo no ERP (o estoque do kit fica zero)" }
    end

    # Fotos do ERP: se a lista (url + variação, na ordem) não mudou, não baixa de novo; se mudou, troca as fotos do ERP.
    # Imagens de referência anexadas no Lunna não são tocadas. => quantas fotos ficaram.
    def sync_images(product, images, warnings)
      current = product.assets.where(kind: "foto").where.not(source_url: nil).order(:position, :id)
      same = current.map { |a| [ a.source_url, a.variation_key ] } == images.map { |i| [ i[:url], i[:variation_key] ] }
      return current.size if same

      current.delete_all
      pos = 0
      images.each do |img|
        bytes, mime = @downloader.call(img[:url])
        unless bytes && mime
          warnings << "imagem não baixada: #{img[:url].split('/').last.to_s.first(60)}"
          next
        end
        product.assets.create!(kind: "foto", mime: mime, data: bytes, source_url: img[:url], variation_key: img[:variation_key],
                               name: img[:url].split("/").last.to_s.split("?").first.to_s.first(120), position: pos += 1)
      end
      pos
    end

    # => [bytes, mime] ou nil. Segue até 3 redirecionamentos; só PNG/JPG/WEBP até 8 MB.
    def download(url, limit = 3)
      uri = URI.parse(url)
      return nil unless uri.is_a?(URI::HTTP) && limit.positive?

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: IMAGE_TIMEOUT, read_timeout: IMAGE_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
      return download(res["location"], limit - 1) if res.is_a?(Net::HTTPRedirection) && res["location"]
      return nil unless res.is_a?(Net::HTTPSuccess)

      mime = MIMES[res.content_type.to_s.downcase] || sniff(res.body)
      return nil unless mime && res.body.bytesize <= 25.megabytes

      bytes, mime = ImageOptimizer.call(res.body, mime) # até 1.600 px, ~150–250 KB (decisão do usuário, 27/11/2026)
      bytes.bytesize <= CatalogProductAsset::MAX_BYTES ? [ bytes, mime ] : nil
    rescue StandardError
      nil
    end

    def sniff(bytes)
      head = bytes.to_s.byteslice(0, 12).to_s.b
      return "image/jpeg" if head.start_with?("\xFF\xD8".b)
      return "image/png" if head.start_with?("\x89PNG".b)
      return "image/webp" if head[0, 4] == "RIFF" && head[8, 4] == "WEBP"

      nil
    end
  end
end
