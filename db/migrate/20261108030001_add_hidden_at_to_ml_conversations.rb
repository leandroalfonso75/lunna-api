class AddHiddenAtToMlConversations < ActiveRecord::Migration[8.1]
  def change
    # "Excluir" conversa: o ML não apaga mensagens de pós-venda; o Lunna tira da lista (volta se o comprador escrever de novo)
    add_column :ml_conversations, :hidden_at, :datetime
  end
end
