# Idempotency anchor for the weekly accountability digest.
# A row records that a tenant received their digest for the given week.
# The unique (tenant_id, week_starting) constraint guarantees we never
# double-send if WeeklyDigestJob runs twice in the same calendar week.
class WeeklyDigestDelivery < ApplicationRecord
  belongs_to :tenant

  validates :tenant, presence: true
  validates :week_starting, presence: true
  validates :delivered_at, presence: true
  validates :week_starting, uniqueness: { scope: :tenant_id }
end
