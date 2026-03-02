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

ActiveRecord::Schema[7.1].define(version: 2026_02_26_021000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "alerts", force: :cascade do |t|
    t.bigint "hypothesis_id", null: false
    t.string "severity", null: false
    t.text "summary", null: false
    t.text "evidence_chain"
    t.text "recommended_action"
    t.string "status", default: "open"
    t.string "assigned_to"
    t.text "analyst_notes"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "domain", default: "cybersecurity", null: false
    t.index ["domain"], name: "index_alerts_on_domain"
    t.index ["hypothesis_id"], name: "index_alerts_on_hypothesis_id"
    t.index ["severity"], name: "index_alerts_on_severity"
    t.index ["status"], name: "index_alerts_on_status"
  end

  create_table "blackboard_logs", force: :cascade do |t|
    t.string "event_type"
    t.string "eventable_type", null: false
    t.bigint "eventable_id", null: false
    t.datetime "processed_at"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["eventable_type", "eventable_id"], name: "index_blackboard_logs_on_eventable"
  end

  create_table "board_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.string "eventable_type"
    t.bigint "eventable_id"
    t.text "metadata"
    t.datetime "published_at"
    t.datetime "processed_at"
    t.string "job_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_board_events_on_event_type"
    t.index ["eventable_type", "eventable_id"], name: "index_board_events_on_eventable"
    t.index ["processed_at"], name: "index_board_events_on_processed_at"
    t.index ["published_at"], name: "index_board_events_on_published_at"
  end

  create_table "control_shell_decisions", force: :cascade do |t|
    t.string "decision_type", null: false
    t.bigint "knowledge_source_id"
    t.bigint "hypothesis_id"
    t.text "reasoning"
    t.json "context", default: {}
    t.string "outcome"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["decision_type"], name: "index_control_shell_decisions_on_decision_type"
    t.index ["hypothesis_id"], name: "index_control_shell_decisions_on_hypothesis_id"
    t.index ["knowledge_source_id"], name: "index_control_shell_decisions_on_knowledge_source_id"
  end

  create_table "critiques", force: :cascade do |t|
    t.bigint "hypothesis_id", null: false
    t.string "critique_type", null: false
    t.text "content", null: false
    t.float "persuasiveness", default: 0.5
    t.string "proposed_by"
    t.boolean "rebutted", default: false
    t.text "rebuttal"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "llm_call_id"
    t.index ["critique_type"], name: "index_critiques_on_critique_type"
    t.index ["hypothesis_id"], name: "index_critiques_on_hypothesis_id"
    t.index ["llm_call_id"], name: "index_critiques_on_llm_call_id"
    t.index ["rebutted"], name: "index_critiques_on_rebutted"
  end

  create_table "evidence_windows", force: :cascade do |t|
    t.datetime "time_start", null: false
    t.datetime "time_end", null: false
    t.jsonb "sensor_mix", default: {}, null: false
    t.integer "event_ids", default: [], null: false, array: true
    t.string "selection_policy", default: "stratified", null: false
    t.string "window_hash", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "domain", default: "cybersecurity", null: false
    t.index ["created_at"], name: "index_evidence_windows_on_created_at"
    t.index ["domain"], name: "index_evidence_windows_on_domain"
    t.index ["window_hash"], name: "index_evidence_windows_on_window_hash", unique: true
  end

  create_table "historical_knowledge_entries", force: :cascade do |t|
    t.bigint "alert_id"
    t.bigint "hypothesis_id"
    t.string "domain", default: "cybersecurity", null: false
    t.string "knowledge_type", default: "common_public_scan", null: false
    t.text "match_attack_type"
    t.text "match_signature"
    t.text "operator_severity", null: false
    t.text "operator_name", null: false
    t.text "notes", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_historical_knowledge_entries_on_active"
    t.index ["alert_id"], name: "index_historical_knowledge_entries_on_alert_id"
    t.index ["domain", "match_attack_type", "active"], name: "idx_hke_domain_attack_active"
    t.index ["domain"], name: "index_historical_knowledge_entries_on_domain"
    t.index ["hypothesis_id"], name: "index_historical_knowledge_entries_on_hypothesis_id"
    t.index ["knowledge_type"], name: "index_historical_knowledge_entries_on_knowledge_type"
    t.index ["operator_severity"], name: "index_historical_knowledge_entries_on_operator_severity"
  end

  create_table "hypotheses", force: :cascade do |t|
    t.string "attack_type"
    t.string "technique_id"
    t.text "description", null: false
    t.float "confidence", default: 0.5
    t.string "status", default: "proposed"
    t.string "proposed_by"
    t.bigint "parent_hypothesis_id"
    t.json "supporting_evidence", default: []
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "llm_call_id"
    t.bigint "evidence_window_id"
    t.string "domain", default: "cybersecurity", null: false
    t.index ["attack_type"], name: "index_hypotheses_on_attack_type"
    t.index ["confidence"], name: "index_hypotheses_on_confidence"
    t.index ["domain"], name: "index_hypotheses_on_domain"
    t.index ["evidence_window_id"], name: "index_hypotheses_on_evidence_window_id"
    t.index ["llm_call_id"], name: "index_hypotheses_on_llm_call_id"
    t.index ["parent_hypothesis_id"], name: "index_hypotheses_on_parent_hypothesis_id"
    t.index ["status"], name: "index_hypotheses_on_status"
  end

  create_table "hypothesis_observables", force: :cascade do |t|
    t.bigint "hypothesis_id", null: false
    t.bigint "observable_id", null: false
    t.text "relevance_explanation"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hypothesis_id", "observable_id"], name: "idx_on_hypothesis_id_observable_id_2b7d3c860d", unique: true
    t.index ["hypothesis_id"], name: "index_hypothesis_observables_on_hypothesis_id"
    t.index ["observable_id"], name: "index_hypothesis_observables_on_observable_id"
  end

  create_table "knowledge_sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "role", null: false
    t.string "model", default: "claude-sonnet-4-20250514"
    t.text "system_prompt"
    t.json "trigger_conditions", default: {}
    t.boolean "active", default: true
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "provider", default: "default", null: false
    t.index ["active"], name: "index_knowledge_sources_on_active"
    t.index ["role"], name: "index_knowledge_sources_on_role"
    t.index ["role"], name: "index_knowledge_sources_on_role_unique", unique: true
  end

  create_table "llm_calls", force: :cascade do |t|
    t.bigint "knowledge_source_id", null: false
    t.string "role", null: false
    t.string "model"
    t.integer "items_count", default: 1
    t.integer "duration_ms"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.boolean "success", default: true
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "cache_hit_tokens"
    t.integer "cache_miss_tokens"
    t.boolean "fallback", default: false, null: false
    t.string "provider"
    t.decimal "cost_usd", precision: 12, scale: 8
    t.index ["created_at"], name: "index_llm_calls_on_created_at"
    t.index ["knowledge_source_id"], name: "index_llm_calls_on_knowledge_source_id"
    t.index ["role"], name: "index_llm_calls_on_role"
  end

  create_table "observables", force: :cascade do |t|
    t.string "source_type", null: false
    t.string "source_name"
    t.text "raw_data", null: false
    t.text "normalized_description"
    t.json "entity_extractions", default: {}
    t.datetime "observed_at", null: false
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "llm_call_id"
    t.string "domain", default: "cybersecurity", null: false
    t.index ["domain", "created_at"], name: "index_observables_on_domain_and_created_at"
    t.index ["domain"], name: "index_observables_on_domain"
    t.index ["llm_call_id"], name: "index_observables_on_llm_call_id"
    t.index ["observed_at"], name: "index_observables_on_observed_at"
    t.index ["source_type"], name: "index_observables_on_source_type"
  end

  create_table "sensor_configurations", force: :cascade do |t|
    t.string "platform", null: false
    t.string "name", null: false
    t.string "source_type", null: false
    t.string "log_path"
    t.string "description"
    t.boolean "enabled", default: false
    t.json "parser_options", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "last_read_position", default: 0
    t.datetime "last_read_at"
    t.string "last_error"
    t.integer "poll_interval_seconds", default: 300
    t.string "domain", default: "cybersecurity", null: false
    t.jsonb "filter_patterns", default: [], null: false
    t.integer "filter_drop_count_total", default: 0, null: false
    t.integer "filter_drop_count_last_poll", default: 0, null: false
    t.index ["domain", "platform"], name: "index_sensor_configurations_on_domain_and_platform"
    t.index ["domain"], name: "index_sensor_configurations_on_domain"
    t.index ["platform", "enabled"], name: "index_sensor_configurations_on_platform_and_enabled"
    t.index ["source_type"], name: "index_sensor_configurations_on_source_type"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "system_settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_system_settings_on_key", unique: true
  end

  create_table "verifications", force: :cascade do |t|
    t.bigint "hypothesis_id", null: false
    t.string "verification_type", null: false
    t.string "tool_used"
    t.text "query"
    t.text "result"
    t.boolean "supports_hypothesis"
    t.float "confidence_delta"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "llm_call_id"
    t.index ["hypothesis_id"], name: "index_verifications_on_hypothesis_id"
    t.index ["llm_call_id"], name: "index_verifications_on_llm_call_id"
    t.index ["supports_hypothesis"], name: "index_verifications_on_supports_hypothesis"
    t.index ["verification_type"], name: "index_verifications_on_verification_type"
  end

  add_foreign_key "alerts", "hypotheses"
  add_foreign_key "control_shell_decisions", "hypotheses"
  add_foreign_key "control_shell_decisions", "knowledge_sources"
  add_foreign_key "critiques", "hypotheses"
  add_foreign_key "critiques", "llm_calls"
  add_foreign_key "historical_knowledge_entries", "alerts"
  add_foreign_key "historical_knowledge_entries", "hypotheses"
  add_foreign_key "hypotheses", "evidence_windows"
  add_foreign_key "hypotheses", "hypotheses", column: "parent_hypothesis_id"
  add_foreign_key "hypotheses", "llm_calls"
  add_foreign_key "hypothesis_observables", "hypotheses"
  add_foreign_key "hypothesis_observables", "observables"
  add_foreign_key "llm_calls", "knowledge_sources"
  add_foreign_key "observables", "llm_calls"
  add_foreign_key "verifications", "hypotheses"
  add_foreign_key "verifications", "llm_calls"
end
