# Migração dos produtos do ERP para a ficha completa do Lunna (27/11/2026). Só leitura no ERP.
#   bin/rails "erp:import_products[393797906 383475561]"  → importa (ou atualiza) estes produtos (id no ERP)
#   bin/rails erp:dry_run                                  → ensaio de todos, sem gravar (tmp/erp_ensaio.csv)
#   bin/rails erp:excluded_report                          → inativos/excluídos e removidos (tmp/erp_nao_importados.csv)
#   bin/rails erp:optimize_photos                          → otimiza as fotos já importadas
namespace :erp do
  def erp_company = Company.joins(:olist_connection).first!

  task :import_products, [ :ids ] => :environment do |_, args|
    ids = args[:ids].to_s.split(/[\s,]+/).map(&:to_i).select(&:positive?)
    puts JSON.pretty_generate(Erp::CatalogImport.call(erp_company, erp_ids: ids).to_h)
  end

  desc "Importa (ou atualiza) todos os produtos ativos do ERP (resultado em tmp/erp_importacao.json)"
  task import_all: :environment do
    company = erp_company
    ids = company.olist_products.where(parent_olist_id: nil, status: "A", hidden_at: nil).order(:description).pluck(:olist_id)
    started = Time.current
    r = Erp::CatalogImport.call(company, erp_ids: ids)
    fotos = CatalogProductAsset.joins(:catalog_product).where(catalog_products: { company_id: company.id, source: "erp" }, kind: "foto")
    summary = { pedidos: ids.size, importados: r.imported.size, pulados: r.skipped.size, falhas: r.errors.size,
                fotos: fotos.count, megabytes: (fotos.sum("octet_length(data)") / 1048576.0).round(1), minutos: ((Time.current - started) / 60).round(1) }
    File.write(Rails.root.join("tmp/erp_importacao.json"), JSON.pretty_generate(summary: summary, result: r.to_h))
    puts JSON.pretty_generate(summary)
  end

  task dry_run: :environment do
    r = Erp::CatalogDryRun.new(erp_company).call
    File.write(Rails.root.join("tmp/erp_ensaio.csv"), r[:csv])
    File.write(Rails.root.join("tmp/erp_ensaio.json"), JSON.pretty_generate(r.slice(:summary, :rows)))
    puts JSON.pretty_generate(r[:summary])
  end

  desc "Otimiza as fotos já importadas do ERP (até 1.600 px, ~150–250 KB)"
  task optimize_photos: :environment do
    before = after = count = 0
    CatalogProductAsset.where(kind: "foto").where.not(source_url: nil).find_each do |a|
      before += a.data.bytesize
      bytes, mime = Erp::ImageOptimizer.call(a.data, a.mime)
      a.update_columns(data: bytes, mime: mime, updated_at: Time.current) if bytes.bytesize < a.data.bytesize
      after += a.reload.data.bytesize
      count += 1
    end
    puts "#{count} fotos: #{(before / 1048576.0).round(1)} MB → #{(after / 1048576.0).round(1)} MB"
  end

  task excluded_report: :environment do
    r = Erp::CatalogDryRun.excluded_report(erp_company)
    File.write(Rails.root.join("tmp/erp_nao_importados.csv"), r[:csv])
    puts "#{r[:rows].size} produtos não importados"
  end
end
