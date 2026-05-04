# EscalationDetectorJob
#
# Hourly recurring job. For each :sent SubmissionPrompt, asks
# OnboardingFlow::EscalationCascade for the next NextAction. If one
# fires, records a FlowEvent (the idempotency anchor) and queues the
# matching EscalationMailer.
#
# The FlowEvent.record! is committed BEFORE the mailer enqueue. The
# cascade re-reads the FlowEvent log on the next run, so re-runs and
# concurrent workers see "already escalated at this severity" and
# short-circuit naturally — no duplicate mail.
class EscalationDetectorJob < ApplicationJob
  queue_as :default

  def perform
    SubmissionPrompt
      .where(status: :sent)
      .find_each do |prompt|
        process(prompt)
      end
  end

  private

  def process(prompt)
    action = OnboardingFlow::EscalationCascade.next_action_for(prompt: prompt)
    return if action.nil?

    Current.tenant = prompt.tenant

    FlowEvent.record!(
      event_type: "escalation.#{action.severity}",
      tenant:     prompt.tenant,
      subject:    prompt,
      payload:    action.payload.merge(
        severity:        action.severity.to_s,
        recipient_email: action.recipient_email
      )
    )

    EscalationMailer
      .with(
        prompt:    prompt,
        severity:  action.severity,
        recipient: action.recipient_email,
        payload:   action.payload
      )
      .escalation_email
      .deliver_later
  ensure
    Current.tenant = nil
  end
end
