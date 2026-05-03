class CreateTenantQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :tenant_questions do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.integer :catalog_version, null: false
      t.string :domain, null: false, default: "marketing"
      t.string :key, null: false
      t.integer :position, null: false
      t.text :prompt, null: false
      t.string :default_cadence, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :sent_at
      t.datetime :answered_at
      t.string :outbound_message_id

      t.timestamps
    end

    add_index :tenant_questions, [ :tenant_id, :key, :catalog_version ], unique: true
    add_index :tenant_questions, :outbound_message_id
    add_index :tenant_questions, :status
  end
end
