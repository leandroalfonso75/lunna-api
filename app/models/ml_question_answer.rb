# Resposta enviada pelo Lunna a uma pergunta do Mercado Livre (registro do envio).
class MlQuestionAnswer < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true
end
