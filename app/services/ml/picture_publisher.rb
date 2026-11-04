# Curva ABC > Fotos: publica no anúncio do Mercado Livre as imagens geradas que o usuário aprovou. Escrita no ML
# (admin, com confirmação, registrada no pedido): sobe cada imagem (/pictures/items/upload) e regrava a lista de
# fotos do anúncio = as que já estavam (na mesma ordem) + as novas no fim, até o limite.
#
# Anúncio de catálogo não aceita troca de fotos (o ML usa as do produto do catálogo: "pictures is not modifiable").
# Nesse caso não sobe nada e devolve os anúncios tradicionais do mesmo produto (`alternatives`), onde dá para publicar
# (pedido do usuário em 04/11/2026, MLB6827577574 → MLB6626564772). `target_item_id` publica num deles.
module Ml
  class PicturePublisher
    MAX_PICTURES = 10
    Result = Struct.new(:ok, :message, :published, :alternatives, keyword_init: true)

    # order (opcional): a galeria final na ordem escolhida, a 1ª é a capa: "ml:<id da foto atual>" ou "new:<id da imagem
    # gerada>" (pedido do usuário em 04/11/2026). Foto atual que não vier na lista entra no fim; gerada fora dela não sobe.
    def self.call(job, client:, target_item_id: nil, seller_id: nil, order: nil) = new(job, client, target_item_id, seller_id, order).call

    # Anúncios tradicionais (não catálogo) do mesmo produto do vendedor (mesmo user_product_id).
    def self.alternatives(client, seller_id, item_id)
      info = client.item_info(item_id)
      return [] unless info["catalog_listing"] && info["user_product_id"].present?

      client.items_by_user_product(seller_id, info["user_product_id"]).reject { |id| id == item_id }.filter_map do |id|
        other = client.item_info(id)
        { item_id: id, status: other["status"], pictures: Array(other["pictures"]).size } unless other["catalog_listing"]
      end
    end

    def initialize(job, client, target_item_id, seller_id, order = nil)
      @order = Array(order).map(&:to_s).presence
      @job = job
      @client = client
      @seller_id = seller_id || job.ml_account.seller_id
      @target = target_item_id.presence || job.item_id
    end

    def call
      return invalid_target unless @target == @job.item_id || alternative_ids.include?(@target)

      info = @client.item_info(@target)
      if info["catalog_listing"]
        alts = self.class.alternatives(@client, @seller_id, @target)
        return Result.new(ok: false, published: 0, alternatives: alts,
                          message: "#{@target} é anúncio de catálogo: o Mercado Livre usa as fotos do produto do catálogo e não deixa trocar." +
                                   (alts.any? ? " Dá para publicar no anúncio tradicional do mesmo produto (#{alts.map { |a| a[:item_id] }.join(', ')})." : ""))
      end

      current = Array(info["pictures"]).map { |p| p["id"] }
      approved = @job.generated.select(&:approved).reject { |p| p.ml_picture_id && current.include?(p.ml_picture_id) }
      approved = approved.select { |p| @order.include?("new:#{p.id}") } if @order
      return Result.new(ok: false, message: "Aprove ao menos uma imagem antes de publicar.", published: 0) if approved.empty?

      room = MAX_PICTURES - current.size
      if room <= 0
        return Result.new(ok: false, published: 0,
                          message: "O anúncio já tem #{current.size} fotos (limite de #{MAX_PICTURES}). Tire alguma no Mercado Livre antes.")
      end

      batch = approved.first(room)
      batch.each do |photo|
        next if photo.ml_picture_id # já subiu numa tentativa anterior: reaproveita

        up = @client.upload_picture(photo.data, filename: "lunna-#{@job.id}-#{photo.position + 1}.#{photo.mime.split('/').last}", mime: photo.mime)
        photo.update!(ml_picture_id: up["id"])
      end
      @client.update_item_pictures(@target, gallery(current, batch))
      @job.update!(status: "publicado", published_at: Time.current, publish_error: nil, published_item_id: @target)
      left = approved.size - batch.size
      Result.new(ok: true, published: batch.size,
                 message: "#{batch.size} foto(s) publicada(s) no anúncio #{@target}." +
                          (left.positive? ? " #{left} ficaram de fora pelo limite de #{MAX_PICTURES} fotos." : ""))
    rescue Ml::Client::Error => e
      @job.update!(publish_error: e.message.to_s.first(500))
      Result.new(ok: false, published: 0, message: "O Mercado Livre recusou a publicação: #{e.message.to_s.first(200)}")
    end

    private

    # Ordem final: a escolhida (sem repetir e só com fotos válidas), as atuais que faltaram no fim; sem ordem, atuais + novas.
    def gallery(current, batch)
      return current + batch.map(&:ml_picture_id) unless @order

      by_token = current.to_h { |id| [ "ml:#{id}", id ] }.merge(batch.to_h { |p| [ "new:#{p.id}", p.ml_picture_id ] })
      chosen = @order.filter_map { |t| by_token[t] }.uniq
      chosen + (current - chosen)
    end

    def alternative_ids
      @alternative_ids ||= self.class.alternatives(@client, @seller_id, @job.item_id).map { |a| a[:item_id] }
    end

    def invalid_target
      Result.new(ok: false, published: 0, message: "Só dá para publicar no próprio anúncio ou num anúncio tradicional do mesmo produto.")
    end
  end
end
