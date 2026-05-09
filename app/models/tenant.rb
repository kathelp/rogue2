class Tenant < ApplicationRecord
  # --------------------------------------------------------------------------
  # Encryption
  # --------------------------------------------------------------------------
  encrypts :gm_email, deterministic: true

  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum(
    :status,
    {
      seeded: "seeded",
      pending_confirm: "pending_confirm",
      confirmed: "confirmed",
      active: "active"
    },
    prefix: :status
  )

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  has_many :contacts, dependent: :destroy
  has_many :tenant_questions, dependent: :destroy
  has_many :responsibilities, dependent: :destroy
  has_many :sources, dependent: :destroy
  has_many :requests, dependent: :destroy
  has_many :submission_prompts, dependent: :destroy
  has_many :skipped_questions, dependent: :destroy
  has_many :flow_events, dependent: :destroy

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :dealership_name, presence: true
  validates :gm_name, presence: true
  validates :gm_email, presence: true
  validates :gm_email_normalized, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: {in: statuses.keys}
  validates :onboarding_token, presence: true, uniqueness: true
  validates(
    :first_question_delay_minutes,
    presence: true,
    numericality: {only_integer: true, greater_than_or_equal_to: 0}
  )
  validates :next_question_delay_hours, presence: true, numericality: {only_integer: true, greater_than: 0}
  validates :time_zone, presence: true
  validates :question_catalog_version, presence: true, numericality: {only_integer: true, greater_than: 0}

  # --------------------------------------------------------------------------
  # Callbacks
  # --------------------------------------------------------------------------
  before_validation :normalize_gm_email, on: %i[create update]
  before_validation :generate_onboarding_token, on: :create

  # --------------------------------------------------------------------------
  # Scopes
  # --------------------------------------------------------------------------
  scope(
    :in_onboarding_silence,
    -> (threshold: 7.days) {
      where(status: [:confirmed, :active])
        .where("last_gm_reply_at IS NULL OR last_gm_reply_at < ?", threshold.ago)
    }
  )

  # --------------------------------------------------------------------------
  # State machine helpers
  # --------------------------------------------------------------------------
  def confirm!
    return false if status_confirmed? || status_active?

    update!(status: :confirmed, confirmed_at: Time.current)

    # Materialize the question catalog exactly once, idempotently.
    # TenantQuestion rows are created on first confirm; re-confirming
    # (e.g., via console) is safe because materialize_for uses find_or_create_by!.
    Rogue::QuestionCatalog::Marketing::V1.materialize_for(tenant: self)

    true
  end

  # --------------------------------------------------------------------------
  # Signed ID helpers (per purpose)
  # --------------------------------------------------------------------------
  def gm_confirm_signed_id(expires_in: 72.hours)
    signed_id(purpose: :gm_confirm, expires_in: expires_in)
  end

  def self.find_by_gm_confirm_signed_id(signed_id)
    find_signed(signed_id, purpose: :gm_confirm)
  end

  def self.find_by_gm_confirm_signed_id!(signed_id)
    find_signed!(signed_id, purpose: :gm_confirm)
  end

  def dashboard_signed_id(expires_in: 8.days)
    signed_id(purpose: :dashboard_drilldown, expires_in: expires_in)
  end

  def self.find_by_dashboard_signed_id(signed_id)
    find_signed(signed_id, purpose: :dashboard_drilldown)
  end

  # --------------------------------------------------------------------------
  # Onboarding address helpers (A1 — plus-addressing)
  # --------------------------------------------------------------------------
  def onboarding_address
    domain = Rails.application.credentials.dig(:inbound_email_domain) || "inbound.rogue.example"
    "#{dealership_name} Onboarding <onboarding+#{onboarding_token}@#{domain}>"
  end

  def onboarding_reply_to
    onboarding_address
  end

  private

  def normalize_gm_email
    return if gm_email.blank?

    # Decrypt before normalizing (encrypts gem exposes the plaintext via accessor)
    normalized = gm_email.downcase.strip
    self.gm_email = normalized
    self.gm_email_normalized = normalized
  end

  def generate_onboarding_token
    return if onboarding_token.present?

    loop do
      token = SecureRandom.base58(16)
      self.onboarding_token = token
      break unless Tenant.exists?(onboarding_token: token)
    end
  end
end
