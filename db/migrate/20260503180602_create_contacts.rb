class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table(:contacts) do |t|
      t.references(:tenant, null: false, foreign_key: true, index: true)
      t.string(:email, null: false)
      t.string(:email_normalized, null: false)
      t.references(:vendor, foreign_key: true, index: true)
      t.string(:classification, null: false)
      t.string(:display_name)

      t.timestamps
    end

    add_index(:contacts, [:tenant_id, :email_normalized], unique: true)
  end
end
