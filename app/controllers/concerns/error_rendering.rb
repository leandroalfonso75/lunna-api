# Envelope de erro uniforme pra API inteira: { "errors": ["..."] } com o
# status certo.
module ErrorRendering
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :render_invalid
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  end

  private

  def render_errors(messages, status:)
    render json: { errors: Array(messages) }, status: status
  end

  def render_not_found(_exception)
    render_errors([ "não encontrado" ], status: :not_found)
  end

  def render_invalid(exception)
    render_errors(exception.record.errors.full_messages, status: :unprocessable_content)
  end

  def render_parameter_missing(exception)
    render_errors([ exception.message ], status: :unprocessable_content)
  end
end
