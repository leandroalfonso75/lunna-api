# Gera as fotos do pedido fora do request (cada imagem leva de 10 a 40 s na OpenRouter); a tela acompanha por polling.
module Ai
  class PhotoGenerationJob < ApplicationJob
    queue_as :default

    def perform(job_id)
      job = MlPhotoJob.find_by(id: job_id)
      return unless job&.status == "gerando"

      Ai::PhotoGenerator.call(job)
      job.update!(status: "pronto", error: nil)
    rescue Ai::PhotoGenerator::Error => e
      job&.update!(status: job.generated.any? ? "pronto" : "erro", error: e.message)
    rescue StandardError => e
      Rails.logger.error("Ai::PhotoGenerationJob: #{e.class}: #{e.message.to_s.first(200)}")
      job&.update!(status: job.generated.any? ? "pronto" : "erro", error: "Não foi possível gerar as fotos agora.")
    end
  end
end
