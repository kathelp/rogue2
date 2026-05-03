class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.string :domain, null: false
      t.references :vendor, foreign_key: true, index: true
      t.string :responsibility_key, null: false
      t.string :submission_method
      t.datetime :configured_at
      t.references :configured_by_contact, foreign_key: { to_table: :contacts }, index: true

      t.timestamps
    end

    add_index :sources, [ :tenant_id, :domain, :responsibility_key ], unique: true
  end
end
