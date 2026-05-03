class SkippedQuestion < ApplicationRecord
  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant
  belongs_to :tenant_question

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :tenant_question, presence: true
  validates :skipped_at, presence: true
end
