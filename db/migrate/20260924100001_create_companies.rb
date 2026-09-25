class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies, id: :uuid do |t|
      t.string :name, null: false
      t.decimal :tax_pct, precision: 6, scale: 2, null: false, default: 11.3
      t.decimal :min_margin_pct, precision: 6, scale: 2, null: false, default: 9
      t.decimal :abc_cut_a, precision: 6, scale: 2, null: false, default: 80
      t.decimal :abc_cut_b, precision: 6, scale: 2, null: false, default: 95
      t.decimal :group_up_pct, precision: 6, scale: 2, null: false, default: 10
      t.decimal :group_down_pct, precision: 6, scale: 2, null: false, default: -15

      t.timestamps
    end
  end
end
