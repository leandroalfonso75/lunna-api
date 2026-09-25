class Session < ApplicationRecord
  belongs_to :user

  class << self
    # Gera um token bruto, grava só o digest (SHA256) e devolve [session, token].
    # O token bruto só existe aqui, na resposta do login/cadastro — nunca no banco.
    def start!(user, request)
      token = SecureRandom.urlsafe_base64(32)

      session = create!(
        user: user,
        token_digest: digest(token),
        expires_at: 30.days.from_now,
        ip: request.remote_ip,
        user_agent: request.user_agent
      )

      [ session, token ]
    end

    # Só devolve a sessão se o digest bater e ela ainda não tiver expirado.
    def find_by_token(token)
      return nil if token.blank?

      where("expires_at > ?", Time.current).find_by(token_digest: digest(token))
    end

    def digest(token)
      Digest::SHA256.hexdigest(token)
    end
  end
end
