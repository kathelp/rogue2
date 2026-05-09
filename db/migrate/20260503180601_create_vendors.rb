class CreateVendors < ActiveRecord::Migration[8.1]
  def change
    create_table(:vendors) do |t|
      t.string(:name, null: false)
      t.string(:domains, array: true, null: false, default: [])
      t.string(:aliases, array: true, null: false, default: [])
      t.string(:categories, array: true, null: false, default: [])
      t.references(:parent_vendor, foreign_key: {to_table: :vendors}, index: true)
      t.string(:regions, array: true, null: false, default: [])
      t.string(:state, null: false, default: "active")
      t.string(:source, null: false)
      t.references(:created_by_tenant, foreign_key: {to_table: :tenants}, index: true)

      t.timestamps
    end

    add_index(:vendors, :domains, using: :gin)
    add_index(:vendors, :state)
  end
end
