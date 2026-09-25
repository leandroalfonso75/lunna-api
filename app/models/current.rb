# Atributos por requisição, setados pela concern Authentication a partir do
# Bearer token. Resetados automaticamente ao fim de cada requisição.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :company, :session
end
