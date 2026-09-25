# `before_action :authenticate!` lê `Authorization: Bearer <token>`, resolve
# a Session e seta Current.session/user/company. Controllers públicos (auth de
# cadastro/login, callback do ML) usam `skip_before_action :authenticate!`.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  private

  def authenticate!
    session = bearer_token && Session.find_by_token(bearer_token)

    unless session
      return render_errors([ "não autenticado" ], status: :unauthorized)
    end

    Current.session = session
    Current.user = session.user
    Current.company = session.user.company
  end

  def bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.delete_prefix("Bearer ").strip.presence
  end

  def require_admin!
    return if Current.user&.admin?

    render_errors([ "sem permissão" ], status: :forbidden)
  end
end
