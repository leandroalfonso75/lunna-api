# Implantação da referência fixa da redução de margem (Promoções, 27/11/2026). Só grava referências no Lunna; nada
# muda no Mercado Livre. Uso: bin/rails promotions:init_drop_refs
namespace :promotions do
  desc "Grava a margem de hoje como referência da redução de margem de cada anúncio em promoção"
  task init_drop_refs: :environment do
    MlAccount.find_each do |account|
      n = Painel::PromotionDropRef.initialize_all!(account)
      puts "#{account.nickname}: #{n} referências gravadas"
    rescue StandardError => e
      puts "#{account.nickname}: erro #{e.class}: #{e.message}"
    end
  end
end
