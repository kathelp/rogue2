class SubmissionPrompt < ApplicationRecord
  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum :status, {
    pending: "pending",
    sent: "sent",
    fulfilled: "fulfilled",
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

  # --------------------------------------------------------------------------
  # Signed ID helpers (per purpose)
  # --------------------------------------------------------------------------
  def submission_form_signed_id(expires_in: 14.days)
    signed_id(purpose: :submission_form, expires_in: expires_in)
  end

  def self.find_by_submission_form_signed_id(signed_id)
    find_signed(signed_id, purpose: :submission_form)
  end
end
