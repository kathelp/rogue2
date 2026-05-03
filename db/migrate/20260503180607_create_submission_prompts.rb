class CreateSubmissionPrompts < ActiveRecord::Migration[8.1]
  def change
    create_table :submission_prompts do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :request, null: false, foreign_key: true, index: true
      t.datetime :scheduled_for, null: false
      t.datetime :sent_at
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :submission_prompts, :scheduled_for
    add_index :submission_prompts, :status
  end
end
