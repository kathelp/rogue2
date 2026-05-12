# OnboardingFlow::EnqueueFirstQuestionJob
#
# Finds the first pending TenantQuestion for a confirmed tenant and dispatches
# the question email for immediate delivery. The first question is intentionally
# exempt from both the per-tenant delay and the business-hours envelope so the
# GM sees momentum the instant they confirm. Subsequent questions go through
# OnboardingFlow::EnqueueNextQuestionJob and resume both gates.
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

    question = tenant
      .tenant_questions
      .where(status: "pending")
      .order(:position)
      .first
    return if question.nil?

    # Pre-generate a deterministic Message-ID so we can persist it before delivery.
    message_id = generate_message_id(tenant, question)

    sent_at = Time.current

    OnboardingMailer
      .with(tenant: tenant, tenant_question: question, message_id: message_id)
      .question_email
      .deliver_later

    # Persist tracking state on the question row.
    question.update!(
      status: "sent",
      sent_at: sent_at,
      outbound_message_id: message_id
    )

    FlowEvent.record!(
      event_type: "question.sent",
      tenant: tenant,
      subject: question,
      payload: {message_id: message_id, deliver_at: sent_at.iso8601}
    )
  end

  private

  def generate_message_id(tenant, question)
    domain = Rails.application.credentials.dig(:inbound_email_domain) || "inbound.rogue.example"
    "<onboarding-q-#{tenant.id}-#{question.id}-#{SecureRandom.hex(8)}@#{domain}>"
  end
end
