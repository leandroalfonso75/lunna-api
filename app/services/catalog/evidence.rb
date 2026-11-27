# "Criar Produto com IA": junta as evidências que a IA pode usar para o rascunho do produto, e só elas.
#   - texto colado e observações do usuário;
#   - links: anúncio do Mercado Livre (MLB...) lido pela API do ML (título, atributos, descrição); outros sites, o texto
#     da página (até TEXT_LIMIT caracteres; só endereços públicos);
#   - SKUs de referência (kit e variações que são kit): o cadastro do ERP sincronizado no Lunna e o anúncio do ML com o
#     mesmo SKU (título, marca, modelo, atributos preenchidos);
#   - imagens de referência anexadas (vão para o modelo de visão).
# Cada bloco leva a origem, para a IA citar de onde veio cada dado e o "Para conferir" apontar o que faltou.
module Catalog
  class Evidence
    TEXT_LIMIT = 12_000
    MAX_LINKS = 5
    ML_ITEM = /MLB-?(\d{6,})/i

    Result = Struct.new(:blocks, :images, :skus, :warnings, keyword_init: true)

    def self.call(product, http: nil, ml_client: nil) = new(product, http: http, ml_client: ml_client).call

    def initialize(product, http: nil, ml_client: nil)
      @product = product
      @company = product.company
      @http = http
      @ml_client = ml_client
      @warnings = []
    end

    def call
      blocks = []
      refs = @product.references.to_h
      # kit com "usar como referências os produtos do kit": Links e Texto ficam de fora (desabilitados na tela)
      unless components_only?
        blocks << "TEXTO DO USUÁRIO:\n#{refs['text'].to_s.strip.first(TEXT_LIMIT)}" if refs["text"].present?
        Array(refs["links"]).map { |l| l.is_a?(Hash) ? l["url"] : l }.compact_blank.uniq.first(MAX_LINKS).each do |url|
          text = link_text(url.to_s.strip)
          blocks << "LINK #{url}:\n#{text}" if text.present?
        end
      end
      blocks << "OBSERVAÇÕES DO USUÁRIO:\n#{@product.notes.strip.first(4000)}" if @product.notes.present?
      skus = reference_skus
      blocks.concat(skus.map { |sku| sku_block(sku) }.compact)
      Result.new(blocks: blocks, images: @product.reference_images.map(&:data_url), skus: skus, warnings: @warnings)
    end

    private

    # a caixa só vale com componentes informados (a tela também esconde e desmarca sem eles)
    def components_only? = @product.kind == "kit" && @product.use_component_references && !@product.no_reference_skus && @product.kit_components.any?

    def reference_skus
      list = case @product.kind
      when "kit" then @product.kit_components.map { |c| c["sku"] }
      when "variations" then (@product.common_components + @product.variations.flat_map { |v| v["kit"] ? v["components"] : [] }).map { |c| c["sku"] }
      else []
      end
      list.compact_blank.uniq.first(20)
    end

    def sku_block(sku)
      erp = @company.olist_products.where(sku: sku).where.not(status: "E").order(updated_at: :desc).first
      items = MlItem.where(ml_account_id: @company.ml_accounts.select(:id), sku: sku).order(sold_quantity: :desc).limit(2).to_a
      if erp.nil? && items.empty?
        @warnings << "SKU #{sku} não foi encontrado nos produtos do ERP nem nos anúncios."
        return nil
      end
      lines = [ "SKU DE REFERÊNCIA #{sku}:" ]
      lines << "- cadastro no ERP: #{erp.description}#{erp.gtin.present? ? " · EAN #{erp.gtin}" : ''}#{erp.unit.present? ? " · unidade #{erp.unit}" : ''}" if erp
      items.each_with_index do |it, i|
        lines << "- anúncio #{it.item_id}: #{it.title}#{it.brand.present? ? " · marca #{it.brand}" : ''}#{it.model.present? ? " · modelo #{it.model}" : ''}"
        # atributos com valor (nome: valor) do anúncio mais vendido do SKU, lidos na hora pela API do ML
        attrs = i.zero? ? live_attributes(it.item_id) : []
        lines << "  atributos: #{attrs.join('; ')}" if attrs.any?
        # com "usar como referências os produtos do kit", vai também a descrição do anúncio do componente
        if i.zero? && components_only? && (desc = listing_description(it.item_id)).present?
          lines << "  descrição do anúncio: #{desc}"
        end
      end
      lines.join("\n")
    end

    def listing_description(item_id)
      client = ml_client
      return nil unless client

      client.item_description(item_id)["plain_text"].to_s.squish.first(3000).presence
    rescue StandardError
      nil
    end

    def live_attributes(item_id)
      client = ml_client
      return [] unless client

      Array(client.item_full(item_id)["attributes"]).filter_map do |a|
        next if a["value_name"].blank? || %w[SELLER_SKU GTIN ITEM_CONDITION].include?(a["id"])

        "#{a['name']}: #{a['value_name']}"
      end.first(40)
    rescue StandardError
      []
    end

    def link_text(url)
      if (m = url.match(ML_ITEM))
        ml_item_text("MLB#{m[1]}") || page_text(url)
      else
        page_text(url)
      end
    end

    def ml_item_text(item_id)
      client = ml_client
      return nil unless client

      item = client.item_full(item_id)
      desc = (client.item_description(item_id)["plain_text"] rescue nil)
      attrs = Array(item["attributes"]).filter_map { |a| "#{a['name']}: #{a['value_name']}" if a["value_name"].present? }
      [ "Título: #{item['title']}", "Condição: #{item['condition']}", ("Atributos: #{attrs.join('; ')}" if attrs.any?),
        ("Descrição: #{desc.to_s.first(TEXT_LIMIT)}" if desc.present?) ].compact.join("\n")
    rescue StandardError => e
      @warnings << "Não foi possível ler o anúncio #{item_id} pela API do Mercado Livre (#{e.class.name.demodulize})."
      nil
    end

    def ml_client
      return @ml_client if @ml_client

      account = @company.ml_accounts.order(:created_at).find { |a| a.access_token.present? }
      return nil unless account

      Ml::OAuth.refresh!(account)
      @ml_client = Ml::Client.new(access_token: account.access_token)
    rescue StandardError
      nil
    end

    def page_text(url)
      uri = URI.parse(url)
      unless %w[http https].include?(uri.scheme) && public_host?(uri.host)
        @warnings << "Link ignorado (endereço inválido ou interno): #{url}"
        return nil
      end
      res = http.get(url) { |req| req.headers["User-Agent"] = "Mozilla/5.0 (compatible; LunnaBot/1.0)" }
      return (@warnings << "O link #{url} respondeu #{res.status}; não foi lido.") && nil unless res.status == 200

      html = res.body.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
      html = html.gsub(%r{<(script|style|noscript)[^>]*>.*?</\1>}mi, " ")
      text = CGI.unescapeHTML(html.gsub(/<[^>]+>/, " ")).squish
      text.first(TEXT_LIMIT).presence
    rescue URI::InvalidURIError, Faraday::Error => e
      @warnings << "Não foi possível abrir o link #{url} (#{e.class.name.demodulize})."
      nil
    end

    def public_host?(host)
      return false if host.blank?

      Resolv.getaddresses(host).then { |ips| ips.any? && ips.none? { |ip| private_ip?(ip) } }
    rescue StandardError
      false
    end

    def private_ip?(ip)
      addr = IPAddr.new(ip)
      %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16 0.0.0.0/8 ::1/128 fc00::/7 fe80::/10]
        .any? { |net| IPAddr.new(net).include?(addr) }
    rescue IPAddr::InvalidAddressError
      true
    end

    def http
      @http ||= Faraday.new { |f| f.options.timeout = 15; f.options.open_timeout = 5 }
    end
  end
end
