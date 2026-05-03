class CreateResponsibilities < ActiveRecord::Migration[8.1]
  def change
    create_table :responsibilities do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :tenant_question, null: false, foreign_key: true, index: true
      t.references :primary_contact, foreign_key: { to_table: :contacts }, index: true
      t.jsonb :fallback_contact_emails, null: false, default: []
      t.boolean :gm_self_assigned, null: false, default: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :responsibilities, :status
  end
end
