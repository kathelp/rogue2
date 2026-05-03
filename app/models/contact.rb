class Contact < ApplicationRecord
  # --------------------------------------------------------------------------
  # Encryption
  # --------------------------------------------------------------------------
  encrypts :email, deterministic: true

  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum :classification, {
    internal_staff: "internal_staff",
    vendor_user: "vendor_user",
    unknown: "unknown"
  }, prefix: :classification

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant
  belongs_to :vendor, optional: true

  has_many :responsibilities, foreign_key: :primary_contact_id, dependent: :nullify, inverse_of: :primary_contact
  has_many :sourced_as_configured_by, class_name: "Source", foreign_key: :configured_by_contact_id, dependent: :nullify, inverse_of: :configured_by_contact

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :email, presence: true
  validates :email_normalized, presence: true
  validates :classification, presence: true, inclusion: { in: classifications.keys }
  validates :email_normalized, uniqueness: { scope: :tenant_id }

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------
  before_validation :normalize_email, on: %i[create update]

  # --------------------------------------------------------------------------
  # Scopes
  # --------------------------------------------------------------------------
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }

  # --------------------------------------------------------------------------
  # Class methods
  # --------------------------------------------------------------------------
  # Idempotent find-or-create on (tenant, email_normalized). Safe to call
  # multiple times with the same inputs — returns the existing record.
  def self.find_or_create_for_email(tenant:, email:, classification:, vendor: nil)
    normalized = email.to_s.downcase.strip
    find_or_create_by!(tenant: tenant, email_normalized: normalized) do |contact|
      contact.email = normalized
      contact.classification = classification
      contact.vendor = vendor
    end
  end

  private

  def normalize_email
    return if email.blank?

    normalized = email.downcase.strip
    self.email = normalized
    self.email_normalized = normalized
  end
end
