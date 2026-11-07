# Uma alteração do Lunna num anúncio do Mercado Livre (título ou ficha técnica), com antes/depois e o resultado.
class MlItemEdit < ApplicationRecord
  belongs_to :ml_account
  belongs_to :user, optional: true
end
