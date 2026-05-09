class Responsibility < ApplicationRecord
  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum(
    :status,
    {
      active: "active",
      superseded: "superseded"
    },
    prefix: :status
  )

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant
  belongs_to :tenant_question
  belongs_to :primary_contact, class_name: "Contact", optional: true

  has_many :sources, dependent: :destroy

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :tenant_question, presence: true
  validates :status, presence: true
  # Allow empty array — presence: true would reject [] (falsy for blank?).
  # Custom check: the column must not be nil (it may be an empty array).
  validate :fallback_contact_emails_must_be_array

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------
  # Returns the primary email for this responsibility.
  # When gm_self_assigned: returns the tenant's gm_email_normalized.
  # Otherwise: returns the primary contact's email_normalized.
  def primary_email
    if gm_self_assigned?
      tenant.gm_email_normalized
    else
      primary_contact&.email_normalized
    end
  end

  private

  def fallback_contact_emails_must_be_array
    errors.add(:fallback_contact_emails, "must be an array (may be empty)") unless fallback_contact_emails.is_a?(Array)
  end
end
