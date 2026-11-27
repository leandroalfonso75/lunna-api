# Migração dos produtos do ERP para a ficha completa do Lunna (27/11/2026). Só leitura no ERP.
#   bin/rails "erp:import_products[393797906 383475561]"  → importa (ou atualiza) estes produtos (id no ERP)
#   bin/rails erp:dry_run                                  → ensaio de todos, sem gravar (tmp/erp_ensaio.csv)
#   bin/rails erp:excluded_report                          → inativos/excluídos e removidos (tmp/erp_nao_importados.csv)
namespace :erp do
  def erp_company = Company.joins(:olist_connection).first!

  task :import_products, [ :ids ] => :environment do |_, args|
    ids = args[:ids].to_s.split(/[\s,]+/).map(&:to_i).select(&:positive?)
    puts JSON.pretty_generate(Erp::CatalogImport.call(erp_company, erp_ids: ids).to_h)
  end

  task dry_run: :environment do
    r = Erp::CatalogDryRun.new(erp_company).call
    File.write(Rails.root.join("tmp/erp_ensaio.csv"), r[:csv])
    File.write(Rails.root.join("tmp/erp_ensaio.json"), JSON.pretty_generate(r.slice(:summary, :rows)))
    puts JSON.pretty_generate(r[:summary])
  end

  task excluded_report: :environment do
    r = Erp::CatalogDryRun.excluded_report(erp_company)
    File.write(Rails.root.join("tmp/erp_nao_importados.csv"), r[:csv])
    puts "#{r[:rows].size} produtos não importados"
  end
end
