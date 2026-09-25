# Parâmetros de negócio da Curva ABC (DECISOES §3), já com os nomes de saída
# da SPEC 10.5 (`cut_a`/`cut_b`/`up_pct`/`down_pct` em vez das colunas
# `abc_cut_a`/`abc_cut_b`/`group_up_pct`/`group_down_pct` de `companies`).
module Abc
  Params = Struct.new(:tax_pct, :min_margin_pct, :cut_a, :cut_b, :up_pct, :down_pct, keyword_init: true) do
    def self.from(company)
      new(
        tax_pct: company.tax_pct.to_f,
        min_margin_pct: company.min_margin_pct.to_f,
        cut_a: company.abc_cut_a.to_f,
        cut_b: company.abc_cut_b.to_f,
        up_pct: company.group_up_pct.to_f,
        down_pct: company.group_down_pct.to_f
      )
    end
  end
end
