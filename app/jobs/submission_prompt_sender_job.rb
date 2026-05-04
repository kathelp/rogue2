# SubmissionPromptSenderJob
#
# Hourly recurring job (declared in `config/recurring.yml`).
# Finds SubmissionPrompt rows that are due (scheduled_for <= now)
# and still :pending, transitions them to :sent (the synchronisation
# point), and queues the appropriate mailer based on the Source's
# submission_method.
#
# Idempotency: the `:pending → :sent` UPDATE is the lock. Concurrent
# workers race the UPDATE; the loser sees affected_rows == 0 and
# does not enqueue mail. Re-runs after a prompt is already :sent or
# :fulfilled are no-ops.
#
# Per AC-HAPPY-1, AC-HAPPY-3, AC-HAPPY-5.
class SubmissionPromptSenderJob < ApplicationJob
  queue_as :default

  def perform
    SubmissionPrompt
      .where(status: :pending)
      .where("scheduled_for <= ?", Time.current)
      .find_each do |prompt|
        send_for(prompt)
      end
  end

  private

  def send_for(prompt)
    affected = SubmissionPrompt
      .where(id: prompt.id, status: :pending)
      .update_all(status: :sent, sent_at: Time.current, updated_at: Time.current)

    return if affected.zero?

    prompt.reload

    source = source_for(prompt)
    method = source&.submission_method.to_s

    if method == "form"
      SubmissionMailer.with(prompt: prompt).prompt_email.deliver_later
    else
      SubmissionMailer.with(prompt: prompt).adapter_pending_email.deliver_later
    end

    FlowEvent.record!(
      event_type: "submission.prompt_sent",
      tenant:     prompt.tenant,
      subject:    prompt,
      payload:    { method: method.presence || "unknown", request_id: prompt.request_id }
    )
  end

  def source_for(prompt)
    prompt.request.source
  end
end
