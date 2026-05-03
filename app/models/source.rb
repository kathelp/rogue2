class Source < ApplicationRecord
  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum :submission_method, {
    form: "form",
    csv: "csv",
    api_post: "api_post"
  }, prefix: :submission_method, allow_nil: true

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant
  belongs_to :vendor, optional: true
  belongs_to :configured_by_contact, class_name: "Contact", optional: true

  has_many :requests, dependent: :destroy
  has_many :responsibilities, dependent: :nullify

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :domain, presence: true
  validates :responsibility_key, presence: true
  validates :responsibility_key, uniqueness: { scope: %i[tenant_id domain] }
end
