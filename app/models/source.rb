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
  # Note: Source ↔ Responsibility join is implicit via
  # (tenant_id, responsibility_key) ↔ (tenant_id, tenant_question.key) —
  # there is no source_id FK on responsibilities. Code that needs the
  # join uses an explicit lookup (e.g. Setup::Completion does this).
  # The phantom `has_many :responsibilities` declaration was removed
  # in TASK-005 cleanup (TASK-001 reflection action item).

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :domain, presence: true
  validates :responsibility_key, presence: true
  validates :responsibility_key, uniqueness: { scope: %i[tenant_id domain] }
end
