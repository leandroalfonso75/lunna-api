# SPEC 9 — chama a Claude API em streaming com a gem oficial `anthropic`.
# Cliente global memoizado (thread-safe, reaproveitado entre requisições).
# `stream.text` já filtra só os deltas de texto dos `content_block_delta`.
module Ai
  class ActionPlan
    class Error < StandardError; end

    def self.client
      @client ||= Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"), timeout: 120)
    end

    def self.stream(prompt, &block)
      response = client.messages.stream(
        model: ENV.fetch("ANTHROPIC_MODEL", "claude-opus-5").to_sym,
        max_tokens: 16_000,
        system_: prompt[:system],
        messages: [ { role: "user", content: prompt[:user] } ]
      )
      response.text.each(&block)
    rescue KeyError
      raise Error, "Integração com a IA não configurada."
    rescue Anthropic::Errors::RateLimitError
      raise Error, "Limite de uso atingido, tente em instantes."
    rescue Anthropic::Errors::PermissionDeniedError, Anthropic::Errors::AuthenticationError
      raise Error, "Sem permissão para gerar o plano."
    rescue Anthropic::Errors::APIConnectionError, Anthropic::Errors::APIStatusError
      raise Error, "Não foi possível gerar o plano agora. Tente de novo."
    end
  end
end
