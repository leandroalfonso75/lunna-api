# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_31_040001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ai_plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "item_id", null: false
    t.string "status", default: "pending", null: false
    t.text "text", default: "", null: false
    t.string "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ml_account_id", "item_id"], name: "index_ai_plans_on_ml_account_id_and_item_id", unique: true
  end

  create_table "companies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.decimal "tax_pct", precision: 6, scale: 2, default: "11.3", null: false
    t.decimal "min_margin_pct", precision: 6, scale: 2, default: "9.0", null: false
    t.decimal "abc_cut_a", precision: 6, scale: 2, default: "80.0", null: false
    t.decimal "abc_cut_b", precision: 6, scale: 2, default: "95.0", null: false
    t.decimal "group_up_pct", precision: 6, scale: 2, default: "10.0", null: false
    t.decimal "group_down_pct", precision: 6, scale: 2, default: "-15.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "openrouter_api_key"
    t.string "ai_model"
    t.decimal "fixed_expenses_pct", precision: 6, scale: 2, default: "3.0", null: false
    t.decimal "max_margin_pct", precision: 6, scale: 2
    t.boolean "promo_routine_enabled", default: false, null: false
    t.string "promo_routine_mode", default: "simulation", null: false
    t.boolean "promo_allow_margin_drop", default: false, null: false
    t.decimal "promo_margin_drop_tolerance", precision: 5, scale: 2
    t.boolean "promo_include_catalog", default: false, null: false
    t.integer "promo_schedule_hour", default: 3, null: false
    t.jsonb "promo_schedule_days", default: [0, 1, 2, 3, 4, 5, 6], null: false
    t.string "promo_margin_basis", default: "after_ads", null: false
    t.string "promo_price_target", default: "min", null: false
    t.boolean "promo_allow_price_increase", default: false, null: false
    t.boolean "promo_allow_lightning", default: false, null: false
    t.integer "ads_cost_days", default: 15, null: false
  end

  create_table "item_metrics", primary_key: "item_id", id: :string, force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "title", collation: "pt-BR-x-icu"
    t.string "status"
    t.string "sku"
    t.string "listing_type"
    t.boolean "full"
    t.boolean "free_shipping"
    t.boolean "catalog"
    t.integer "variations"
    t.decimal "price", precision: 12, scale: 2
    t.decimal "original_price", precision: 12, scale: 2
    t.integer "stock"
    t.integer "quality_score"
    t.integer "visits_7d", default: 0, null: false
    t.integer "prev_visits_7d", default: 0, null: false
    t.integer "visits_30d", default: 0, null: false
    t.integer "prev_visits_30d", default: 0, null: false
    t.integer "units_today", default: 0, null: false
    t.integer "units_7d", default: 0, null: false
    t.integer "prev_units_7d", default: 0, null: false
    t.integer "units_30d", default: 0, null: false
    t.integer "prev_units_30d", default: 0, null: false
    t.decimal "revenue_7d", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "prev_revenue_7d", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "revenue_30d", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "prev_revenue_30d", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "net_after_fee_7d", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "fees_30d", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "conversion_7d", precision: 8, scale: 2
    t.decimal "prev_conversion_7d", precision: 8, scale: 2
    t.decimal "conversion_30d", precision: 8, scale: 2
    t.decimal "prev_conversion_30d", precision: 8, scale: 2
    t.integer "units_delta"
    t.decimal "coverage_days", precision: 10, scale: 1
    t.decimal "coverage_30d", precision: 10, scale: 1
    t.datetime "computed_at"
    t.index ["ml_account_id", "revenue_30d"], name: "index_item_metrics_on_ml_account_id_and_revenue_30d"
    t.index ["ml_account_id", "status"], name: "index_item_metrics_on_ml_account_id_and_status"
    t.index ["ml_account_id", "units_7d"], name: "index_item_metrics_on_ml_account_id_and_units_7d"
    t.index ["ml_account_id"], name: "index_item_metrics_on_ml_account_id"
  end

  create_table "ml_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.bigint "seller_id", null: false
    t.string "nickname"
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "expires_at"
    t.string "scope"
    t.string "status", default: "active", null: false
    t.text "last_error"
    t.datetime "orders_backfilled_at"
    t.datetime "visits_synced_at"
    t.uuid "connected_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "ads_synced_at"
    t.bigint "ads_advertiser_id"
    t.datetime "ads_recent_synced_at"
    t.datetime "promotions_synced_at"
    t.index ["company_id"], name: "index_ml_accounts_on_company_id"
    t.index ["connected_by_user_id"], name: "index_ml_accounts_on_connected_by_user_id"
    t.index ["seller_id"], name: "index_ml_accounts_on_seller_id", unique: true
  end

  create_table "ml_ad_campaigns", primary_key: ["ml_account_id", "campaign_id"], force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.bigint "campaign_id", null: false
    t.string "name"
    t.string "status"
    t.string "strategy"
    t.string "channel"
    t.decimal "acos_target", precision: 8, scale: 2
    t.decimal "roas_target", precision: 8, scale: 2
    t.decimal "budget", precision: 12, scale: 2
    t.decimal "daily_budget", precision: 12, scale: 2
    t.boolean "automatic_budget"
    t.datetime "date_created"
    t.datetime "last_updated"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "auction", default: {}, null: false
    t.datetime "auction_synced_at"
  end

  create_table "ml_ad_daily_metrics", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.bigint "campaign_id", null: false
    t.date "date", null: false
    t.integer "clicks", default: 0, null: false
    t.bigint "prints", default: 0, null: false
    t.decimal "cost", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "direct_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "indirect_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "direct_units", default: 0, null: false
    t.integer "indirect_units", default: 0, null: false
    t.integer "units", default: 0, null: false
    t.integer "organic_units", default: 0, null: false
    t.decimal "organic_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.index ["ml_account_id", "campaign_id", "date"], name: "index_ml_ad_daily_unique", unique: true
  end

  create_table "ml_ad_day_syncs", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.date "date", null: false
    t.datetime "fetched_at", null: false
    t.index ["ml_account_id", "date"], name: "index_ml_ad_day_syncs_unique", unique: true
  end

  create_table "ml_ad_decisions", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "key", null: false
    t.string "signal", null: false
    t.string "klass", null: false
    t.string "title"
    t.text "action"
    t.decimal "value", precision: 12, scale: 2
    t.string "status", null: false
    t.jsonb "before", default: {}, null: false
    t.uuid "user_id"
    t.datetime "decided_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ml_account_id", "key", "signal", "decided_at"], name: "idx_on_ml_account_id_key_signal_decided_at_1d40952a75"
    t.index ["ml_account_id"], name: "index_ml_ad_decisions_on_ml_account_id"
    t.index ["user_id"], name: "index_ml_ad_decisions_on_user_id"
  end

  create_table "ml_ad_item_dailies", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "item_id", null: false
    t.date "date", null: false
    t.bigint "campaign_id"
    t.decimal "cost", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "clicks", default: 0, null: false
    t.bigint "prints", default: 0, null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "units", default: 0, null: false
    t.index ["ml_account_id", "date"], name: "index_ml_ad_item_dailies_on_ml_account_id_and_date"
    t.index ["ml_account_id", "item_id", "date"], name: "index_ml_ad_item_dailies_unique", unique: true
  end

  create_table "ml_ad_items", primary_key: ["ml_account_id", "item_id"], force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "item_id", null: false
    t.bigint "campaign_id"
    t.bigint "ad_group_id"
    t.string "title"
    t.string "status"
    t.decimal "price", precision: 12, scale: 2
    t.string "thumbnail"
    t.string "permalink"
    t.string "listing_type_id"
    t.string "logistic_type"
    t.boolean "catalog_listing"
    t.boolean "buy_box_winner"
    t.boolean "recommended"
    t.boolean "has_discount"
    t.string "condition"
    t.datetime "date_created"
    t.jsonb "metrics", default: {}, null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "family_id"
    t.string "family_name"
    t.string "image_quality"
    t.string "domain_id"
    t.index ["ml_account_id", "campaign_id"], name: "index_ml_ad_items_on_ml_account_id_and_campaign_id"
    t.index ["ml_account_id", "family_id"], name: "index_ml_ad_items_on_ml_account_id_and_family_id"
  end

  create_table "ml_catalog_checks", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "item_id", null: false
    t.bigint "action_id"
    t.string "status", default: "aguardando", null: false
    t.integer "attempts", default: 0, null: false
    t.string "ml_status"
    t.string "message"
    t.datetime "check_at"
    t.datetime "checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_ml_catalog_checks_on_action_id"
    t.index ["ml_account_id", "status"], name: "index_ml_catalog_checks_on_ml_account_id_and_status"
    t.index ["ml_account_id"], name: "index_ml_catalog_checks_on_ml_account_id"
  end

  create_table "ml_costs", force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "sku", null: false
    t.decimal "cost", precision: 12, scale: 2
    t.decimal "extra", precision: 12, scale: 2, default: "0.0", null: false
    t.string "source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "sku"], name: "index_ml_costs_on_company_id_and_sku", unique: true
    t.index ["company_id"], name: "index_ml_costs_on_company_id"
  end

  create_table "ml_full_stocks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "inventory_id", null: false
    t.integer "available_units", default: 0, null: false
    t.integer "not_available_units", default: 0, null: false
    t.integer "total_units", default: 0, null: false
    t.jsonb "not_available_detail", default: [], null: false
    t.datetime "synced_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ml_account_id", "inventory_id"], name: "index_ml_full_stocks_on_ml_account_id_and_inventory_id", unique: true
  end

  create_table "ml_item_visits", primary_key: ["item_id", "day"], force: :cascade do |t|
    t.string "item_id", null: false
    t.uuid "ml_account_id", null: false
    t.date "day", null: false
    t.integer "visits", null: false
    t.index ["ml_account_id", "day"], name: "index_ml_item_visits_on_ml_account_id_and_day"
    t.index ["ml_account_id"], name: "index_ml_item_visits_on_ml_account_id"
  end

  create_table "ml_items", primary_key: "item_id", id: :string, force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.bigint "seller_id", null: false
    t.string "title", collation: "pt-BR-x-icu"
    t.string "status"
    t.jsonb "sub_status", default: [], null: false
    t.decimal "price", precision: 12, scale: 2
    t.decimal "original_price", precision: 12, scale: 2
    t.decimal "sale_price", precision: 12, scale: 2
    t.decimal "regular_price", precision: 12, scale: 2
    t.integer "available_quantity"
    t.integer "sold_quantity"
    t.string "listing_type_id"
    t.string "category_id"
    t.string "logistic_type"
    t.boolean "free_shipping"
    t.boolean "catalog_listing"
    t.string "sku"
    t.integer "variations_count"
    t.string "permalink"
    t.string "thumbnail"
    t.decimal "health", precision: 5, scale: 2
    t.integer "pictures_count"
    t.boolean "has_video"
    t.jsonb "attrs_filled", default: [], null: false
    t.jsonb "attrs_missing_required", default: [], null: false
    t.jsonb "attrs_missing_main", default: [], null: false
    t.string "brand"
    t.string "model"
    t.integer "description_len"
    t.integer "quality_score"
    t.string "quality_level"
    t.jsonb "quality_pending", default: [], null: false
    t.decimal "fee_now", precision: 12, scale: 2
    t.decimal "ship_cost", precision: 12, scale: 2
    t.jsonb "price_ref"
    t.decimal "fee_at_ref", precision: 12, scale: 2
    t.decimal "ship_at_ref", precision: 12, scale: 2
    t.datetime "date_created"
    t.datetime "last_updated"
    t.datetime "details_checked_at"
    t.datetime "quality_checked_at"
    t.datetime "synced_at"
    t.jsonb "inventory_refs", default: [], null: false
    t.jsonb "fee_details"
    t.string "catalog_product_id"
    t.jsonb "item_relations", default: [], null: false
    t.string "catalog_status"
    t.decimal "catalog_price_to_win", precision: 12, scale: 2
    t.decimal "catalog_winner_price", precision: 12, scale: 2
    t.jsonb "catalog_reasons", default: [], null: false
    t.datetime "catalog_checked_at"
    t.index ["ml_account_id", "status"], name: "index_ml_items_on_ml_account_id_and_status"
    t.index ["ml_account_id"], name: "index_ml_items_on_ml_account_id"
  end

  create_table "ml_oauth_states", primary_key: "state", id: :string, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.index ["company_id"], name: "index_ml_oauth_states_on_company_id"
    t.index ["user_id"], name: "index_ml_oauth_states_on_user_id"
  end

  create_table "ml_order_items", primary_key: ["order_id", "item_id"], force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "item_id", null: false
    t.integer "quantity"
    t.decimal "unit_price", precision: 12, scale: 2
    t.decimal "sale_fee", precision: 12, scale: 2
    t.string "title"
    t.string "sku"
    t.string "listing_type_id"
    t.bigint "variation_id"
    t.index ["item_id"], name: "index_ml_order_items_on_item_id"
  end

  create_table "ml_orders", primary_key: "order_id", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "status"
    t.datetime "date_created"
    t.datetime "date_closed"
    t.decimal "total_amount", precision: 12, scale: 2
    t.datetime "synced_at"
    t.jsonb "payload"
    t.bigint "shipping_id"
    t.bigint "pack_id"
    t.bigint "buyer_id"
    t.string "buyer_nickname"
    t.decimal "paid_amount", precision: 12, scale: 2
    t.jsonb "shipment"
    t.datetime "shipment_synced_at"
    t.jsonb "claims"
    t.datetime "claims_synced_at"
    t.index ["ml_account_id", "date_created"], name: "index_ml_orders_on_ml_account_id_and_date_created"
    t.index ["ml_account_id"], name: "index_ml_orders_on_ml_account_id"
    t.index ["shipping_id"], name: "index_ml_orders_on_shipping_id"
  end

  create_table "ml_promotion_actions", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "item_id", null: false
    t.string "kind", null: false
    t.string "source", null: false
    t.string "from_promotion_id"
    t.string "from_type"
    t.string "from_name"
    t.decimal "from_price", precision: 12, scale: 2
    t.decimal "from_margin_pct", precision: 8, scale: 2
    t.string "to_promotion_id"
    t.string "to_type"
    t.string "to_name"
    t.decimal "to_price", precision: 12, scale: 2
    t.decimal "to_margin_pct", precision: 8, scale: 2
    t.decimal "gain", precision: 12, scale: 2
    t.boolean "ok", default: false, null: false
    t.string "error"
    t.uuid "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "run_id"
    t.decimal "from_profit", precision: 12, scale: 2
    t.decimal "to_profit", precision: 12, scale: 2
    t.string "forced_reason"
    t.index ["ml_account_id", "created_at"], name: "index_ml_promotion_actions_on_ml_account_id_and_created_at"
    t.index ["run_id"], name: "index_ml_promotion_actions_on_run_id"
    t.index ["user_id"], name: "index_ml_promotion_actions_on_user_id"
  end

  create_table "ml_promotion_offers", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "item_id", null: false
    t.string "promotion_id"
    t.string "promotion_type", null: false
    t.string "sub_type"
    t.string "name"
    t.string "status"
    t.decimal "price", precision: 12, scale: 2
    t.decimal "original_price", precision: 12, scale: 2
    t.decimal "min_price", precision: 12, scale: 2
    t.decimal "max_price", precision: 12, scale: 2
    t.decimal "max_top_price", precision: 12, scale: 2
    t.decimal "suggested_price", precision: 12, scale: 2
    t.decimal "fixed_amount", precision: 12, scale: 2
    t.decimal "meli_percentage", precision: 6, scale: 2
    t.decimal "seller_percentage", precision: 6, scale: 2
    t.datetime "start_date"
    t.datetime "finish_date"
    t.jsonb "fees"
    t.jsonb "payload"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ml_account_id", "item_id"], name: "index_ml_promotion_offers_on_ml_account_id_and_item_id"
    t.index ["ml_account_id", "promotion_id"], name: "index_ml_promotion_offers_on_ml_account_id_and_promotion_id"
  end

  create_table "ml_promotion_runs", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "mode", null: false
    t.string "trigger", null: false
    t.string "status", default: "running", null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.jsonb "totals", default: {}, null: false
    t.string "error"
    t.uuid "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ml_account_id", "started_at"], name: "index_ml_promotion_runs_on_ml_account_id_and_started_at"
    t.index ["user_id"], name: "index_ml_promotion_runs_on_user_id"
  end

  create_table "ml_promotion_settings", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "item_id", null: false
    t.string "sku"
    t.decimal "min_margin_pct", precision: 6, scale: 2
    t.decimal "max_margin_pct", precision: 6, scale: 2
    t.boolean "apply_to_sku", default: false, null: false
    t.boolean "automation_enabled", default: true, null: false
    t.uuid "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "limit_mode", default: "margin", null: false
    t.decimal "min_price", precision: 12, scale: 2
    t.decimal "max_price", precision: 12, scale: 2
    t.boolean "apply_to_variations", default: false, null: false
    t.text "rules_note"
    t.index ["ml_account_id", "item_id"], name: "index_ml_promotion_settings_unique", unique: true
    t.index ["updated_by_id"], name: "index_ml_promotion_settings_on_updated_by_id"
  end

  create_table "ml_promotions", force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.string "promotion_id", null: false
    t.string "promotion_type", null: false
    t.string "sub_type"
    t.string "name"
    t.string "status"
    t.datetime "start_date"
    t.datetime "finish_date"
    t.datetime "deadline_date"
    t.jsonb "payload"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ml_account_id", "promotion_id"], name: "index_ml_promotions_unique", unique: true
  end

  create_table "ml_sync_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ml_account_id", null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.boolean "ok"
    t.integer "items"
    t.integer "orders"
    t.text "detail"
    t.index ["ml_account_id", "started_at"], name: "index_ml_sync_runs_on_ml_account_id_and_started_at"
    t.index ["ml_account_id"], name: "index_ml_sync_runs_on_ml_account_id"
  end

  create_table "olist_changes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id"
    t.bigint "olist_product_id", null: false
    t.string "kind", null: false
    t.jsonb "before", default: {}, null: false
    t.jsonb "request", default: {}, null: false
    t.jsonb "response", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "created_at"], name: "index_olist_changes_on_company_id_and_created_at"
    t.index ["user_id"], name: "index_olist_changes_on_user_id"
  end

  create_table "olist_connections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "connected_by_user_id"
    t.text "access_token", null: false
    t.text "refresh_token", null: false
    t.datetime "expires_at"
    t.datetime "refresh_expires_at"
    t.string "status", default: "active", null: false
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "costs_status"
    t.datetime "costs_checked_at"
    t.index ["company_id"], name: "index_olist_connections_on_company_id", unique: true
    t.index ["connected_by_user_id"], name: "index_olist_connections_on_connected_by_user_id"
  end

  create_table "olist_oauth_states", primary_key: "state", id: :string, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_olist_oauth_states_on_company_id"
    t.index ["user_id"], name: "index_olist_oauth_states_on_user_id"
  end

  create_table "olist_products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.bigint "olist_id", null: false
    t.string "sku"
    t.string "description"
    t.string "kind"
    t.string "status"
    t.string "variation_kind"
    t.string "unit"
    t.string "gtin"
    t.decimal "price", precision: 14, scale: 2
    t.decimal "promo_price", precision: 14, scale: 2
    t.decimal "cost_price", precision: 14, scale: 2
    t.decimal "avg_cost_price", precision: 14, scale: 2
    t.decimal "stock_balance", precision: 14, scale: 3
    t.decimal "stock_reserved", precision: 14, scale: 3
    t.decimal "stock_available", precision: 14, scale: 3
    t.string "stock_location"
    t.jsonb "stock_deposits", default: [], null: false
    t.datetime "olist_created_at"
    t.datetime "olist_updated_at"
    t.datetime "synced_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "parent_olist_id"
    t.jsonb "variation_ids", default: [], null: false
    t.datetime "variations_source_updated_at"
    t.decimal "fifo_unit_cost", precision: 14, scale: 4
    t.decimal "fifo_stock_value", precision: 16, scale: 2
    t.decimal "fifo_units", precision: 14, scale: 3
    t.decimal "fifo_units_without_cost", precision: 14, scale: 3
    t.jsonb "fifo_layers", default: [], null: false
    t.decimal "fifo_shortfall", precision: 14, scale: 3
    t.decimal "fifo_balance_at_calc", precision: 14, scale: 3
    t.datetime "fifo_calculated_at"
    t.datetime "movements_synced_at"
    t.jsonb "kit_components", default: [], null: false
    t.datetime "kit_checked_at"
    t.decimal "fifo_last_entry_cost", precision: 12, scale: 4
    t.index ["company_id", "olist_id"], name: "index_olist_products_on_company_id_and_olist_id", unique: true
    t.index ["company_id", "parent_olist_id"], name: "index_olist_products_on_company_id_and_parent_olist_id"
    t.index ["company_id", "sku"], name: "index_olist_products_on_company_id_and_sku"
    t.index ["company_id", "status"], name: "index_olist_products_on_company_id_and_status"
  end

  create_table "olist_stock_movements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.bigint "olist_product_id", null: false
    t.bigint "movement_id", null: false
    t.bigint "deposit_id"
    t.string "kind", null: false
    t.decimal "quantity", precision: 14, scale: 3, default: "0.0", null: false
    t.decimal "price", precision: 14, scale: 4
    t.datetime "moved_at"
    t.string "origin"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "olist_product_id", "moved_at"], name: "index_olist_movements_by_product_date"
    t.index ["company_id", "olist_product_id", "movement_id"], name: "index_olist_movements_unique", unique: true
  end

  create_table "olist_sync_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "requested_by_user_id"
    t.string "trigger", default: "auto", null: false
    t.string "status", default: "running", null: false
    t.integer "products_count"
    t.string "error"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "started_at"], name: "index_olist_sync_runs_on_company_id_and_started_at"
    t.index ["requested_by_user_id"], name: "index_olist_sync_runs_on_requested_by_user_id"
  end

  create_table "radar_collections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "requested_by_user_id"
    t.string "category_path", null: false
    t.string "status", default: "requested", null: false
    t.string "error"
    t.integer "items_count"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "category_path"], name: "index_radar_collections_one_active_per_category", unique: true, where: "((status)::text = ANY (ARRAY[('requested'::character varying)::text, ('collecting'::character varying)::text]))"
    t.index ["company_id"], name: "index_radar_collections_on_company_id"
    t.index ["requested_by_user_id"], name: "index_radar_collections_on_requested_by_user_id"
  end

  create_table "radar_searches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id"
    t.string "category_path", null: false
    t.jsonb "filters", default: {}, null: false
    t.date "data_ref"
    t.integer "total_items", default: 0, null: false
    t.bigint "total_sold", default: 0, null: false
    t.decimal "total_revenue", precision: 16, scale: 2, default: "0.0", null: false
    t.decimal "median_price", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "created_at"], name: "index_radar_searches_on_company_id_and_created_at"
    t.index ["user_id"], name: "index_radar_searches_on_user_id"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.string "ip"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "ai_plans", "ml_accounts", on_delete: :cascade
  add_foreign_key "item_metrics", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_accounts", "companies", on_delete: :cascade
  add_foreign_key "ml_accounts", "users", column: "connected_by_user_id", on_delete: :nullify
  add_foreign_key "ml_ad_campaigns", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_ad_daily_metrics", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_ad_day_syncs", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_ad_decisions", "ml_accounts"
  add_foreign_key "ml_ad_decisions", "users"
  add_foreign_key "ml_ad_item_dailies", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_ad_items", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_catalog_checks", "ml_accounts"
  add_foreign_key "ml_catalog_checks", "ml_promotion_actions", column: "action_id"
  add_foreign_key "ml_costs", "companies", on_delete: :cascade
  add_foreign_key "ml_full_stocks", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_item_visits", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_items", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_oauth_states", "companies", on_delete: :cascade
  add_foreign_key "ml_oauth_states", "users", on_delete: :cascade
  add_foreign_key "ml_order_items", "ml_orders", column: "order_id", primary_key: "order_id", on_delete: :cascade
  add_foreign_key "ml_orders", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_promotion_actions", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_promotion_actions", "ml_promotion_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "ml_promotion_actions", "users", on_delete: :nullify
  add_foreign_key "ml_promotion_offers", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_promotion_runs", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_promotion_runs", "users", on_delete: :nullify
  add_foreign_key "ml_promotion_settings", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_promotion_settings", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "ml_promotions", "ml_accounts", on_delete: :cascade
  add_foreign_key "ml_sync_runs", "ml_accounts", on_delete: :cascade
  add_foreign_key "olist_changes", "companies", on_delete: :cascade
  add_foreign_key "olist_changes", "users", on_delete: :nullify
  add_foreign_key "olist_connections", "companies", on_delete: :cascade
  add_foreign_key "olist_connections", "users", column: "connected_by_user_id", on_delete: :nullify
  add_foreign_key "olist_oauth_states", "companies", on_delete: :cascade
  add_foreign_key "olist_oauth_states", "users", on_delete: :cascade
  add_foreign_key "olist_products", "companies", on_delete: :cascade
  add_foreign_key "olist_stock_movements", "companies", on_delete: :cascade
  add_foreign_key "olist_sync_runs", "companies", on_delete: :cascade
  add_foreign_key "olist_sync_runs", "users", column: "requested_by_user_id", on_delete: :nullify
  add_foreign_key "radar_collections", "companies", on_delete: :cascade
  add_foreign_key "radar_collections", "users", column: "requested_by_user_id", on_delete: :nullify
  add_foreign_key "radar_searches", "companies", on_delete: :cascade
  add_foreign_key "radar_searches", "users", on_delete: :nullify
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "users", "companies", on_delete: :cascade
end
