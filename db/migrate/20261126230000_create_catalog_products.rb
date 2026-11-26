# "Criar Produto com IA" (pedido do usuário em 26/11/2026): o produto é cadastrado no Lunna (rascunho próprio) e só
# depois exportado para o ERP. O modelo é neutro de ERP (Olist hoje; Bling, Upseller etc. depois): os campos seguem a
# estrutura comum de cadastro (dados gerais, complementares, ficha técnica, fiscal, estoque, outros), sem nomes de um
# ERP específico. A exportação fica em adaptadores (Erp::Exporters::*), com o resultado em `erp_exports`.
class CreateCatalogProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_products do |t|
      t.references :company, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false, default: "simple"       # simple | variations | kit
      t.string :status, null: false, default: "rascunho"   # rascunho | em_revisao | pronto

      # dados gerais
      t.string :name
      t.string :sku
      t.string :gtin
      t.string :unit, null: false, default: "UN"
      t.decimal :price, precision: 14, scale: 2
      t.decimal :cost_price, precision: 14, scale: 2
      t.decimal :weight_net, precision: 10, scale: 3       # kg
      t.decimal :weight_gross, precision: 10, scale: 3     # kg
      t.integer :package_width                             # cm inteiros
      t.integer :package_height
      t.integer :package_length
      t.string :package_source                             # usuario | ia | nao_encontrado
      t.boolean :stock_control, null: false, default: true
      t.decimal :initial_stock, precision: 14, scale: 3    # opcional: sem ele, o estoque entra depois (seção Estoque)
      t.decimal :min_stock, precision: 14, scale: 3
      t.decimal :max_stock, precision: 14, scale: 3
      t.string :location
      t.integer :preparation_days

      # fiscal (a IA só sugere em ai_suggestions; o usuário confirma)
      t.string :ncm
      t.string :cest
      t.integer :icms_origin                               # 0 a 8
      t.string :sped_item_type

      # dados complementares e conteúdo
      t.string :brand
      t.string :line
      t.string :model
      t.string :category                                   # caminho completo
      t.string :condition, null: false, default: "novo"    # novo | usado | recondicionado
      t.string :sale_format, null: false, default: "unidade" # unidade | kit | pack
      t.jsonb :titles, null: false, default: []            # sugestões de título (até 60 caracteres, distintos)
      t.text :description
      t.jsonb :technical_sheet, null: false, default: []   # [{ name, value }]
      t.string :keywords
      t.string :seo_title
      t.text :seo_description
      t.string :video_url

      # outros
      t.string :warranty
      t.string :supplier
      t.jsonb :regulatory, null: false, default: {}        # { anvisa: ... }
      t.text :notes                                        # observações do usuário para a IA

      # referências, variações e kit
      t.jsonb :references, null: false, default: {}        # { links: [], text: "" } (imagens em catalog_product_assets)
      t.boolean :no_reference_skus, null: false, default: false # kit: "Não tenho / não quero SKUs de referência"
      t.jsonb :kit_components, null: false, default: []    # kit: [{ sku, quantity }]
      t.jsonb :variation_axes, null: false, default: []    # ["Cor"], ["Voltagem"], ["Cor", "Tamanho"]
      t.jsonb :variations, null: false, default: []        # [{ key, attrs, sku, gtin, price, stock, kit, components }]
      t.jsonb :common_components, null: false, default: [] # variação-kit: itens que vão em todas as variações marcadas como kit

      # IA
      t.jsonb :ai_suggestions, null: false, default: {}    # fiscais e o que não foi aplicado por já ter valor do usuário
      t.jsonb :ai_review, null: false, default: []         # "Para conferir": omissões, divergências, o que falta
      t.datetime :ai_generated_at
      t.string :ai_error

      t.jsonb :erp_exports, null: false, default: {}       # { "olist" => { id, exported_at, error } }
      t.timestamps
    end
    add_index :catalog_products, %i[company_id created_at]

    # imagens do produto: referências anexadas pelo usuário e fotos geradas (etapa de imagens)
    create_table :catalog_product_assets do |t|
      t.references :catalog_product, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false, default: "referencia"   # referencia | foto
      t.string :variation_key                              # foto de uma variação (nil = do produto)
      t.integer :position, null: false, default: 0
      t.string :name
      t.string :mime, null: false
      t.binary :data, null: false
      t.timestamps
    end
  end
end
