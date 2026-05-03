class CreateRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :requests do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :source, null: false, foreign_key: true, index: true
      t.string :metric_key, null: false
      t.string :cadence, null: false
      t.datetime :next_due_at

      t.timestamps
    end
  end
end
