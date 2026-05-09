class TenantQuestion < ApplicationRecord
  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum(
    :status,
    {
      pending: "pending",
      sent: "sent",
      answered: "answered",
      skipped: "skipped"
    },
    prefix: :status
  )

  enum(
    :domain,
    {
      marketing: "marketing"
      # sales and service to be added in future catalog versions
    },
    prefix: :domain
  )

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant

  has_many :responsibilities, dependent: :destroy
  has_many :skipped_questions, dependent: :destroy

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :catalog_version, presence: true, numericality: {only_integer: true, greater_than: 0}
  validates :domain, presence: true
  validates :key, presence: true
  validates :position, presence: true, numericality: {only_integer: true, greater_than: 0}
  validates :prompt, presence: true
  validates :default_cadence, presence: true
  validates :status, presence: true
  validates :key, uniqueness: {scope: %i[tenant_id catalog_version]}
end
