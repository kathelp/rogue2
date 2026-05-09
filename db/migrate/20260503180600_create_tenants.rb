class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table(:tenants) do |t|
      t.string(:dealership_name, null: false)
      t.string(:gm_name, null: false)
      t.string(:gm_email, null: false)
      t.string(:gm_email_normalized, null: false)
      t.string(:status, null: false, default: "pending_confirm")
      t.string(:onboarding_token, null: false)
      t.datetime(:confirmation_sent_at)
      t.datetime(:confirmed_at)
      t.integer(:first_question_delay_minutes, null: false, default: 60)
      t.integer(:next_question_delay_hours, null: false, default: 24)
      t.datetime(:last_gm_reply_at)
      t.string(:time_zone, null: false, default: "America/New_York")
      t.integer(:question_catalog_version, null: false, default: 1)

      t.timestamps
    end

    add_index(:tenants, :gm_email_normalized, unique: true)
    add_index(:tenants, :onboarding_token, unique: true)
    add_index(:tenants, :last_gm_reply_at)
    add_index(:tenants, :status)
  end
end
