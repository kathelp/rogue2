class CreateSkippedQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table(:skipped_questions) do |t|
      t.references(:tenant, null: false, foreign_key: true, index: true)
      t.references(:tenant_question, null: false, foreign_key: true, index: true)
      t.datetime(:skipped_at, null: false)
      t.datetime(:revisited_at)

      t.timestamps
    end
  end
end
