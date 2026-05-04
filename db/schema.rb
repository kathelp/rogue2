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

ActiveRecord::Schema[8.1].define(version: 2026_05_03_180701) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.string "parser_confidence"
    t.string "parser_intent"
    t.jsonb "parser_warnings", default: [], null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "contacts", force: :cascade do |t|
    t.string "classification", null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", null: false
    t.string "email_normalized", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "vendor_id"
    t.index ["tenant_id", "email_normalized"], name: "index_contacts_on_tenant_id_and_email_normalized", unique: true
    t.index ["tenant_id"], name: "index_contacts_on_tenant_id"
    t.index ["vendor_id"], name: "index_contacts_on_vendor_id"
  end

  create_table "flow_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.bigint "tenant_id"
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_flow_events_on_event_type"
    t.index ["occurred_at"], name: "index_flow_events_on_occurred_at"
    t.index ["subject_type", "subject_id"], name: "index_flow_events_on_subject_type_and_subject_id"
    t.index ["tenant_id", "event_type", "occurred_at"], name: "index_flow_events_on_tenant_id_and_event_type_and_occurred_at"
    t.index ["tenant_id"], name: "index_flow_events_on_tenant_id"
  end

  create_table "requests", force: :cascade do |t|
    t.string "cadence", null: false
    t.datetime "created_at", null: false
    t.string "metric_key", null: false
    t.datetime "next_due_at"
    t.bigint "source_id", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id"], name: "index_requests_on_source_id"
    t.index ["tenant_id"], name: "index_requests_on_tenant_id"
  end

  create_table "responsibilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "fallback_contact_emails", default: [], null: false
    t.boolean "gm_self_assigned", default: false, null: false
    t.bigint "primary_contact_id"
    t.string "status", default: "active", null: false
    t.bigint "tenant_id", null: false
    t.bigint "tenant_question_id", null: false
    t.datetime "updated_at", null: false
    t.index ["primary_contact_id"], name: "index_responsibilities_on_primary_contact_id"
    t.index ["status"], name: "index_responsibilities_on_status"
    t.index ["tenant_id"], name: "index_responsibilities_on_tenant_id"
    t.index ["tenant_question_id"], name: "index_responsibilities_on_tenant_question_id"
  end

  create_table "skipped_questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "revisited_at"
    t.datetime "skipped_at", null: false
    t.bigint "tenant_id", null: false
    t.bigint "tenant_question_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_skipped_questions_on_tenant_id"
    t.index ["tenant_question_id"], name: "index_skipped_questions_on_tenant_question_id"
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "configured_at"
    t.bigint "configured_by_contact_id"
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.string "responsibility_key", null: false
    t.string "submission_method"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "vendor_id"
    t.index ["configured_by_contact_id"], name: "index_sources_on_configured_by_contact_id"
    t.index ["tenant_id", "domain", "responsibility_key"], name: "index_sources_on_tenant_id_and_domain_and_responsibility_key", unique: true
    t.index ["tenant_id"], name: "index_sources_on_tenant_id"
    t.index ["vendor_id"], name: "index_sources_on_vendor_id"
  end

  create_table "submission_prompts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fulfilled_at"
    t.bigint "request_id", null: false
    t.datetime "scheduled_for", null: false
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["request_id"], name: "index_submission_prompts_on_request_id"
    t.index ["scheduled_for"], name: "index_submission_prompts_on_scheduled_for"
    t.index ["status"], name: "index_submission_prompts_on_status"
    t.index ["tenant_id"], name: "index_submission_prompts_on_tenant_id"
  end

  create_table "submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.date "period_starting", null: false
    t.bigint "request_id", null: false
    t.bigint "submission_prompt_id", null: false
    t.datetime "submitted_at", null: false
    t.bigint "submitted_by_contact_id", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 18, scale: 4, null: false
    t.index ["request_id", "period_starting"], name: "index_submissions_on_request_period"
    t.index ["request_id"], name: "index_submissions_on_request_id"
    t.index ["submission_prompt_id"], name: "index_submissions_on_submission_prompt_id"
    t.index ["submitted_by_contact_id"], name: "index_submissions_on_submitted_by_contact_id"
    t.index ["tenant_id"], name: "index_submissions_on_tenant_id"
  end

  create_table "tenant_questions", force: :cascade do |t|
    t.datetime "answered_at"
    t.integer "catalog_version", null: false
    t.datetime "created_at", null: false
    t.string "default_cadence", null: false
    t.string "domain", default: "marketing", null: false
    t.string "key", null: false
    t.string "outbound_message_id"
    t.integer "position", null: false
    t.text "prompt", null: false
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["outbound_message_id"], name: "index_tenant_questions_on_outbound_message_id"
    t.index ["status"], name: "index_tenant_questions_on_status"
    t.index ["tenant_id", "key", "catalog_version"], name: "idx_on_tenant_id_key_catalog_version_cdd941a015", unique: true
    t.index ["tenant_id"], name: "index_tenant_questions_on_tenant_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "dealership_name", null: false
    t.integer "first_question_delay_minutes", default: 60, null: false
    t.string "gm_email", null: false
    t.string "gm_email_normalized", null: false
    t.string "gm_name", null: false
    t.datetime "last_gm_reply_at"
    t.integer "next_question_delay_hours", default: 24, null: false
    t.string "onboarding_token", null: false
    t.integer "question_catalog_version", default: 1, null: false
    t.string "status", default: "pending_confirm", null: false
    t.string "time_zone", default: "America/New_York", null: false
    t.datetime "updated_at", null: false
    t.index ["gm_email_normalized"], name: "index_tenants_on_gm_email_normalized", unique: true
    t.index ["last_gm_reply_at"], name: "index_tenants_on_last_gm_reply_at"
    t.index ["onboarding_token"], name: "index_tenants_on_onboarding_token", unique: true
    t.index ["status"], name: "index_tenants_on_status"
  end

  create_table "vendors", force: :cascade do |t|
    t.string "aliases", default: [], null: false, array: true
    t.string "categories", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.bigint "created_by_tenant_id"
    t.string "domains", default: [], null: false, array: true
    t.string "name", null: false
    t.bigint "parent_vendor_id"
    t.string "regions", default: [], null: false, array: true
    t.string "source", null: false
    t.string "state", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_tenant_id"], name: "index_vendors_on_created_by_tenant_id"
    t.index ["domains"], name: "index_vendors_on_domains", using: :gin
    t.index ["parent_vendor_id"], name: "index_vendors_on_parent_vendor_id"
    t.index ["state"], name: "index_vendors_on_state"
  end

  create_table "weekly_digest_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "delivered_at", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.date "week_starting", null: false
    t.index ["tenant_id", "week_starting"], name: "index_weekly_digest_deliveries_on_tenant_week", unique: true
    t.index ["tenant_id"], name: "index_weekly_digest_deliveries_on_tenant_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "contacts", "tenants"
  add_foreign_key "contacts", "vendors"
  add_foreign_key "flow_events", "tenants"
  add_foreign_key "requests", "sources"
  add_foreign_key "requests", "tenants"
  add_foreign_key "responsibilities", "contacts", column: "primary_contact_id"
  add_foreign_key "responsibilities", "tenant_questions"
  add_foreign_key "responsibilities", "tenants"
  add_foreign_key "skipped_questions", "tenant_questions"
  add_foreign_key "skipped_questions", "tenants"
  add_foreign_key "sources", "contacts", column: "configured_by_contact_id"
  add_foreign_key "sources", "tenants"
  add_foreign_key "sources", "vendors"
  add_foreign_key "submission_prompts", "requests"
  add_foreign_key "submission_prompts", "tenants"
  add_foreign_key "submissions", "contacts", column: "submitted_by_contact_id"
  add_foreign_key "submissions", "requests"
  add_foreign_key "submissions", "submission_prompts"
  add_foreign_key "submissions", "tenants"
  add_foreign_key "tenant_questions", "tenants"
  add_foreign_key "vendors", "tenants", column: "created_by_tenant_id"
  add_foreign_key "vendors", "vendors", column: "parent_vendor_id"
  add_foreign_key "weekly_digest_deliveries", "tenants"
end
