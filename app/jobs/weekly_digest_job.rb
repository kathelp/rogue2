# WeeklyDigestJob
#
# Runs weekly (declared in config/recurring.yml). For every confirmed/active
# tenant whose `confirmed_at` is at least 7 days old, queues
# AccountabilityMailer#weekly_digest. Idempotent on (tenant_id, week_starting):
# the unique constraint on `weekly_digest_deliveries` guarantees at most one
# digest per tenant per calendar week, even if the job runs twice.
#
# Per AC-HAPPY-8 / AC-ASYNC-3.
class WeeklyDigestJob < ApplicationJob
  queue_as :default

  def perform
    week_starting = Date.current.beginning_of_week(:monday)

    eligible_tenants.find_each do |tenant|
      send_digest_for(tenant, week_starting: week_starting)
    end
  end

  private

  def eligible_tenants
    Tenant
      .where(status: %w[confirmed active])
      .where("confirmed_at IS NOT NULL AND confirmed_at <= ?", 7.days.ago)
  end

  def send_digest_for(tenant, week_starting:)
    # Insert idempotency row first; if the unique constraint fires, skip
    # delivery — another process already handled this week.
    delivery = WeeklyDigestDelivery.new(
      tenant:        tenant,
      week_starting: week_starting,
      delivered_at:  Time.current
    )

    return unless delivery.save

    AccountabilityMailer
      .with(tenant: tenant)
      .weekly_digest
      .deliver_later

    FlowEvent.record!(
      event_type: "digest.sent",
      tenant:     tenant,
      subject:    delivery,
      payload:    { week_starting: week_starting.iso8601 }
    )
  rescue ActiveRecord::RecordNotUnique
    # Another worker beat us to it — no-op.
    nil
  end
end
