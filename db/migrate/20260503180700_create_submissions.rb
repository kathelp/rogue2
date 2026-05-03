class CreateSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :submissions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :request, null: false, foreign_key: true
      t.references :submission_prompt, null: false, foreign_key: true
      t.references :submitted_by_contact, null: false, foreign_key: { to_table: :contacts }
      t.decimal :value, precision: 18, scale: 4, null: false
      t.text :notes
      t.date :period_starting, null: false
      t.datetime :submitted_at, null: false

      t.timestamps
    end

    add_index :submissions, %i[request_id period_starting], name: "index_submissions_on_request_period"
  end
end
