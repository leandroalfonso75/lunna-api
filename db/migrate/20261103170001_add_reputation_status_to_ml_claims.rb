class AddReputationStatusToMlClaims < ActiveRecord::Migration[8.1]
  # O ML responde affects_reputation como texto ("affected" / "not_affected"), não como verdadeiro/falso. Guarda o texto
  # original e recalcula a coluna booleana de todas as reclamações já importadas (texto "not_affected" tinha virado true).
  def up
    add_column :ml_claims, :reputation_status, :string
    execute <<~SQL
      UPDATE ml_claims
      SET reputation_status = NULLIF(reputation->>'affects_reputation', ''),
          affects_reputation = CASE reputation->>'affects_reputation'
                                 WHEN 'affected' THEN TRUE WHEN 'true' THEN TRUE
                                 WHEN 'not_affected' THEN FALSE WHEN 'false' THEN FALSE
                                 ELSE NULL END
    SQL
  end

  def down
    remove_column :ml_claims, :reputation_status
  end
end
