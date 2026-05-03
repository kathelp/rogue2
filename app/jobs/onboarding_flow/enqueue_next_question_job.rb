# OnboardingFlow::EnqueueNextQuestionJob
#
# Finds the next pending TenantQuestion for a confirmed tenant and schedules
# the question email for delivery, respecting the business-hours envelope.
#
# Args:
#   tenant_id  (Integer)       — required
#   wait_hours (Numeric, nil)  — optional; defaults to tenant.next_question_delay_hours
#
# Idempotent:
# - Returns early if no pending TenantQuestion exists.
# - Trusts the caller to supply the correct wait_hours (adaptive pacing lives
#   in the parser pipeline — Phase 4).
#
# Wired from: Phase 4 parser pipeline (OnboardingMailbox) after each parsed reply.
class OnboardingFlow::EnqueueNextQuestionJob < ApplicationJob
  queue_as :default

  def perform(tenant_id:, wait_hours: nil)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant

    question = tenant.tenant_questions
                     .where(status: "pending")
                     .order(:position)
                     .first
    return if question.nil?

    effective_wait_hours = wait_hours || tenant.next_question_delay_hours

    # Pre-generate a deterministic Message-ID so we can persist it before delivery.
    message_id = generate_message_id(tenant, question)

    # Compute delivery time: wait_hours + business-hours envelope.
    target     = Time.current + effective_wait_hours.hours
    deliver_at = OnboardingFlow::Scheduling.next_business_window(
      after:     target,
      time_zone: tenant.time_zone
    )

    OnboardingMailer
      .with(tenant: tenant, tenant_question: question, message_id: message_id)
      .question_email
      .deliver_later(wait_until: deliver_at)

    # Persist tracking state on the question row.
    question.update!(
      status:              "sent",
      sent_at:             deliver_at,
      outbound_message_id: message_id
    )

    FlowEvent.record!(
      event_type: "question.sent",
      tenant:     tenant,
      subject:    question,
      payload:    { message_id: message_id, deliver_at: deliver_at.iso8601 }
    )
  end

  private

  def generate_message_id(tenant, question)
    domain = Rails.application.credentials.dig(:inbound_email_domain) || "inbound.rogue.example"
    "<onboarding-q-#{tenant.id}-#{question.id}-#{SecureRandom.hex(8)}@#{domain}>"
  end
end
