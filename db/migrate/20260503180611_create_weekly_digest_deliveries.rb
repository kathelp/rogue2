class CreateWeeklyDigestDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table(:weekly_digest_deliveries) do |t|
      t.references(:tenant, null: false, foreign_key: true)
      t.date(:week_starting, null: false)
      t.datetime(:delivered_at, null: false)

      t.timestamps
    end

    add_index(
      :weekly_digest_deliveries,
      %i[tenant_id week_starting],
      unique: true,
      name: "index_weekly_digest_deliveries_on_tenant_week"
    )
  end
end
