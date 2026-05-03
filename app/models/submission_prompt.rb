class SubmissionPrompt < ApplicationRecord
  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum :status, {
    pending: "pending",
    sent: "sent",
    superseded: "superseded"
  }, prefix: :status

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant
  belongs_to :request

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :request, presence: true
  validates :scheduled_for, presence: true
  validates :status, presence: true
end
