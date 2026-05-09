class Submission < ApplicationRecord
  belongs_to :tenant
  belongs_to :request
  belongs_to :submission_prompt
  belongs_to :submitted_by_contact, class_name: "Contact"

  validates :tenant, presence: true
  validates :request, presence: true
  validates :submission_prompt, presence: true
  validates :submitted_by_contact, presence: true
  validates :value, presence: true, numericality: {greater_than_or_equal_to: 0}
  validates :period_starting, presence: true
  validates :submitted_at, presence: true

  scope :for_period, -> (period_starting) { where(period_starting: period_starting) }
end
