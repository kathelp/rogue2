class Request < ApplicationRecord
  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum(
    :cadence,
    {
      weekly: "weekly",
      monthly: "monthly",
      quarterly: "quarterly",
      semi_annual: "semi_annual",
      annual: "annual"
    },
    prefix: :cadence
  )

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant
  belongs_to :source

  has_many :submission_prompts, dependent: :destroy

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :tenant, presence: true
  validates :source, presence: true
  validates :metric_key, presence: true
  validates :cadence, presence: true
end
