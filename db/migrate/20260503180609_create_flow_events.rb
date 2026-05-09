class CreateFlowEvents < ActiveRecord::Migration[8.1]
  def change
    create_table(:flow_events) do |t|
      t.references(:tenant, foreign_key: true, index: true)
      t.string(:event_type, null: false)
      t.string(:actor_type)
      t.bigint(:actor_id)
      t.string(:subject_type)
      t.bigint(:subject_id)
      t.jsonb(:payload, null: false, default: {})
      t.datetime(:occurred_at, null: false)

      t.timestamps
    end

    add_index(:flow_events, :event_type)
    add_index(:flow_events, :occurred_at)
    add_index(:flow_events, [:tenant_id, :event_type, :occurred_at])
    add_index(:flow_events, [:subject_type, :subject_id])
  end
end
