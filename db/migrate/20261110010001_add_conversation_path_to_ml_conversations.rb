class AddConversationPathToMlConversations < ActiveRecord::Migration[8.1]
  def change
    # Conversa com o assistente de IA do ML (ex.: /packs/{pack}/sellers/{seller}/conversations/ai-seller): a resposta vai
    # para esse caminho e para o agente, não para o comprador (10/11/2026, 409 "The conversation ID is invalid").
    add_column :ml_conversations, :conversation_path, :string
    add_column :ml_conversations, :agent_id, :bigint
  end
end
