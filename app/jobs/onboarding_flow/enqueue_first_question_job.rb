# OnboardingFlow::EnqueueFirstQuestionJob
#
# Finds the first pending TenantQuestion for a confirmed tenant and schedules
# the question email for delivery, respecting the business-hours envelope.
#
# Args: tenant_id (Integer)
#
# Idempotent:
# - Returns early if tenant is not confirmed.
# - Returns early if no pending TenantQuestion exists (catalog not materialised
#   yet, or all questions already sent/answered).
#
# Wired from: Onboarding::ConfirmationsController#show after Tenant#confirm!
class OnboardingFlow::EnqueueFirstQuestionJob < ApplicationJob
  queue_as :default

  def perform(tenant_id:)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant&.status_confirmed?

    question = tenant.tenant_questions
                     .where(status: "pending")
                     .order(:position)
                     .first
    return if question.nil?

    # Pre-generate a deterministic Message-ID so we can persist it before delivery.
    message_id = generate_message_id(tenant, question)

    # Compute delivery time: first_question_delay_minutes + business-hours envelope.
    target     = Time.current + tenant.first_question_delay_minutes.minutes
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
