# Agendado a cada 6 h (config/recurring.yml): renova o acesso das conexões do
# Olist. O refresh token vale só 1 dia; sem isto, uma conexão parada por um
# dia inteiro exigiria reconectar. Falha de uma empresa não derruba as outras.
module Olist
  class RefreshAllJob < ApplicationJob
    def perform
      OlistConnection.active.find_each do |connection|
        Olist::OAuth.refresh!(connection, force: true)
      rescue Olist::OAuth::Error => e
        Rails.logger.warn("Olist::RefreshAllJob: conexão #{connection.id} precisa reconectar (#{e.class})")
      end
    end
  end
end
