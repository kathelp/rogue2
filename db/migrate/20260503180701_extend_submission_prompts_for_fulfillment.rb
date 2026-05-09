class ExtendSubmissionPromptsForFulfillment < ActiveRecord::Migration[8.0]
  def change
    add_column(:submission_prompts, :fulfilled_at, :datetime)
  end
end
