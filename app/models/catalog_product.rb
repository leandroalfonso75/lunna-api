# Produto cadastrado no Lunna ("Criar Produto com IA", 26/11/2026). Neutro de ERP: a exportação para o Olist (e outros
# ERPs no futuro) é feita por adaptadores. Três tipos: simple, variations (variações; cada variação pode ser um kit) e
# kit (composição de produtos já existentes).
class CatalogProduct < ApplicationRecord
  KINDS = %w[simple variations kit].freeze
  STATUSES = %w[rascunho em_revisao pronto].freeze
  CONDITIONS = %w[novo usado recondicionado].freeze
  SALE_FORMATS = %w[unidade kit pack].freeze
  TITLE_MAX = 60
  MAX_VARIATIONS = 50
  MAX_REFERENCE_IMAGES = 6

  belongs_to :company
  belongs_to :created_by, class_name: "User", optional: true
  has_many :assets, -> { order(:position, :id) }, class_name: "CatalogProductAsset", dependent: :delete_all

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :condition, inclusion: { in: CONDITIONS }
  validates :sale_format, inclusion: { in: SALE_FORMATS }
  validates :icms_origin, inclusion: { in: 0..8 }, allow_nil: true
  validates :name, length: { maximum: 120 }
  validate :gtins_valid
  validate :variations_valid
  validate :components_valid

  before_validation :normalize

  def reference_images = assets.select { |a| a.kind == "referencia" }

  # Kit com variações (1 produto com variações + 1 produto simples): a grade de variações vale como em "Com variações",
  # cada linha é um kit (variação do pai + o simples, que fica nos itens comuns).
  def variation_kit? = kind == "kit" && kit_with_variations
  def has_variations? = kind == "variations" || variation_kit?

  # SKUs usados como referência/composição: kit simples, itens comuns e itens próprios das variações-kit.
  def component_skus
    list = kind == "kit" && !kit_with_variations ? kit_components : common_components + variations.flat_map { |v| v["kit"] ? Array(v["components"]) : [] }
    list.map { |c| c["sku"] }.compact_blank.uniq
  end

  # Dígito verificador de EAN-8/12/13/14 (GTIN).
  def self.valid_gtin?(code)
    digits = code.to_s.gsub(/\D/, "")
    return false unless [ 8, 12, 13, 14 ].include?(digits.size) && digits == code.to_s.strip

    body = digits[0..-2].chars.map(&:to_i).reverse
    sum = body.each_with_index.sum { |d, i| i.even? ? d * 3 : d }
    (10 - sum % 10) % 10 == digits[-1].to_i
  end

  # Componentes efetivos de uma variação marcada como kit: os comuns + os próprios (mesmo SKU soma a quantidade).
  def components_for(variation)
    return [] unless variation["kit"]

    (Array(common_components) + Array(variation["components"])).each_with_object({}) do |c, acc|
      acc[c["sku"]] = (acc[c["sku"]] || 0) + c["quantity"].to_f
    end.map { |sku, qty| { "sku" => sku, "quantity" => qty } }
  end

  private

  def normalize
    self.titles = Array(titles).map { |t| t.to_s.squish }.compact_blank.uniq.first(6)
    self.technical_sheet = Array(technical_sheet).filter_map do |row|
      name = row["name"].to_s.squish
      value = row["value"].to_s.squish
      { "name" => name, "value" => value } if name.present? && value.present?
    end
    self.variation_axes = Array(variation_axes).map { |a| a.to_s.squish }.compact_blank.uniq.first(3)
    self.variations = Array(variations).each_with_index.map do |v, i|
      v = v.to_h.stringify_keys
      {
        "key" => v["key"].presence || SecureRandom.hex(4), "position" => i,
        "attrs" => v["attrs"].to_h.transform_values { |x| x.to_s.squish }.slice(*variation_axes),
        "sku" => v["sku"].to_s.strip.presence, "gtin" => v["gtin"].to_s.strip.presence,
        "price" => v["price"].presence&.to_s&.tr(",", ".")&.to_f, "stock" => v["stock"].presence&.to_s&.tr(",", ".")&.to_f,
        "kit" => ActiveModel::Type::Boolean.new.cast(v["kit"]) || false, "components" => clean_components(v["components"])
      }
    end
    self.kit_components = clean_components(kit_components)
    self.common_components = clean_components(common_components)
    self.sku = sku.to_s.strip.presence
    self.gtin = gtin.to_s.strip.presence
    self.ncm = ncm.to_s.gsub(/\D/, "").presence
    self.cest = cest.to_s.gsub(/\D/, "").presence
  end

  def clean_components(list)
    Array(list).filter_map do |c|
      c = c.to_h.stringify_keys
      sku = c["sku"].to_s.strip
      qty = c["quantity"].to_s.tr(",", ".").to_f
      { "sku" => sku, "quantity" => qty.positive? ? qty : 1.0 } if sku.present?
    end.uniq { |c| c["sku"] }
  end

  def gtins_valid
    errors.add(:gtin, "inválido (dígito verificador não confere)") if gtin.present? && !self.class.valid_gtin?(gtin)
    codes = Array(variations).filter_map { |v| v["gtin"] }
    codes.each { |g| errors.add(:variations, "EAN #{g} inválido (dígito verificador não confere)") unless self.class.valid_gtin?(g) }
    dup = codes.tally.select { |_, n| n > 1 }.keys
    errors.add(:variations, "EAN repetido entre variações: #{dup.join(', ')}") if dup.any?
    errors.add(:gtin, "igual ao de uma variação") if gtin.present? && codes.include?(gtin)
  end

  def variations_valid
    return unless has_variations?

    errors.add(:variations, "no máximo #{MAX_VARIATIONS}") if variations.size > MAX_VARIATIONS
    skus = variations.filter_map { |v| v["sku"] }
    dup = skus.tally.select { |_, n| n > 1 }.keys
    errors.add(:variations, "SKU repetido entre variações: #{dup.join(', ')}") if dup.any?
    combos = variations.map { |v| v["attrs"].values_at(*variation_axes).map { |x| x.to_s.downcase } }
    errors.add(:variations, "há variações repetidas") if combos.uniq.size != combos.size
  end

  def components_valid
    own = [ sku, *variations.filter_map { |v| v["sku"] } ].compact
    all = kit_components + common_components + variations.flat_map { |v| v["components"] }
    loops = all.map { |c| c["sku"] } & own
    errors.add(:kit_components, "o kit não pode conter o próprio SKU (#{loops.join(', ')})") if loops.any?
  end
end
