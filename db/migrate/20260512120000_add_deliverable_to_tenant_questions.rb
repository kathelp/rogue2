class AddDeliverableToTenantQuestions < ActiveRecord::Migration[8.1]
  def up
    add_column(:tenant_questions, :deliverable, :text)

    execute(
      <<~SQL
        UPDATE tenant_questions
        SET deliverable = lower(regexp_replace(prompt, '\\?$', ''))
        WHERE deliverable IS NULL
      SQL
    )

    change_column_null(:tenant_questions, :deliverable, false)
  end

  def down
    remove_column(:tenant_questions, :deliverable)
  end
end
