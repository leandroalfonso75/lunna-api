# Curva ABC > Fotos: publica no anúncio do Mercado Livre as imagens geradas que o usuário aprovou. Escrita no ML
# (admin, com confirmação, registrada no pedido): sobe cada imagem (/pictures/items/upload) e regrava a lista de
# fotos do anúncio = as que já estavam (na mesma ordem) + as novas no fim, até o limite.
module Ml
  class PicturePublisher
    MAX_PICTURES = 10
    Result = Struct.new(:ok, :message, :published, keyword_init: true)

    def self.call(job, client:) = new(job, client).call

    def initialize(job, client)
      @job = job
      @client = client
    end

    def call
      approved = @job.generated.select(&:approved).reject(&:ml_picture_id)
      return Result.new(ok: false, message: "Aprove ao menos uma imagem antes de publicar.", published: 0) if approved.empty?

      current = @client.item_pictures(@job.item_id).map { |p| p["id"] }
      room = MAX_PICTURES - current.size
      if room <= 0
        return Result.new(ok: false, published: 0,
                          message: "O anúncio já tem #{current.size} fotos (limite de #{MAX_PICTURES}). Tire alguma no Mercado Livre antes.")
      end

      batch = approved.first(room)
      batch.each do |photo|
        up = @client.upload_picture(photo.data, filename: "lunna-#{@job.id}-#{photo.position + 1}.#{photo.mime.split('/').last}", mime: photo.mime)
        photo.update!(ml_picture_id: up["id"])
      end
      @client.update_item_pictures(@job.item_id, current + batch.map(&:ml_picture_id))
      @job.update!(status: "publicado", published_at: Time.current, publish_error: nil)
      left = approved.size - batch.size
      Result.new(ok: true, published: batch.size,
                 message: "#{batch.size} foto(s) publicada(s) no anúncio #{@job.item_id}." +
                          (left.positive? ? " #{left} ficaram de fora pelo limite de #{MAX_PICTURES} fotos." : ""))
    rescue Ml::Client::Error => e
      @job.update!(publish_error: e.message.to_s.first(500))
      Result.new(ok: false, published: 0, message: "O Mercado Livre recusou a publicação: #{e.message.to_s.first(200)}")
    end
  end
end
