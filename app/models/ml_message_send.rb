# Mensagem enviada pelo Lunna numa conversa de pós-venda (registro do envio).
class MlMessageSend < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true
end
