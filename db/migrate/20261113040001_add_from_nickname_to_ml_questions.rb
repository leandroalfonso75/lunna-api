# Perguntas (pedido do usuário em 13/11/2026): quem perguntou — apelido do ML e, se já comprou da loja, o nome da venda.
class AddFromNicknameToMlQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :ml_questions, :from_nickname, :string
    add_column :ml_questions, :from_name, :string
  end
end
