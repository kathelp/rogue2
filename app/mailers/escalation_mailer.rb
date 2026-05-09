class EscalationMailer < ApplicationMailer
  include Threadable

  default from: "Rogue <hello@inbound.rogue.example>"

  # Single-action mailer with severity-driven subject + body.
  #
  # params[:prompt]    - SubmissionPrompt
  # params[:severity]  - :due_soon | :overdue | :fallback_fanout | :gm_nudge
  # params[:recipient] - String (email)
  # params[:payload]   - Hash (severity-specific extras: fallback_index, fallback_chain, etc.)
  def escalation_email
    @prompt = params[:prompt]
    @severity = params[:severity]
    @recipient = params[:recipient]
    @payload = params[:payload] || {}
    @tenant = @prompt.tenant
    @request = @prompt.request
    @source = @request.source
    @form_url = submission_form_url(
      signed_id: @prompt.submission_form_signed_id(expires_in: 14.days)
    )

    mail(
      to: @recipient,
      cc: cc_for(@severity, @payload, @recipient).presence,
      from: onboarding_address(@tenant),
      reply_to: onboarding_address(@tenant),
      subject: subject_for(@severity)
    )
  end

  private

  # On gm_nudge, CC the full responsibility chain (primary + fallbacks) so
  # the GM can reply-all and lean on the people who are supposed to deliver.
  # Other severities have no CC — they're directed at one accountable party.
  def cc_for(severity, payload, recipient)
    return [] unless severity == :gm_nudge

    chain = [payload[:primary_email], *Array(payload[:fallback_chain])].compact
    chain.uniq.reject { |e| e.casecmp?(recipient.to_s) }
  end

  def subject_for(severity)
    metric_label = @request.metric_key.to_s.tr("_", " ")
    period_label = @prompt.scheduled_for.in_time_zone(@tenant.time_zone).strftime("%B %Y")

    case severity
    when :due_soon
      days_left = days_until_period_end
      "#{@tenant.dealership_name}: #{metric_label} due in #{days_left} days"
    when :overdue, :fallback_fanout
      "#{@tenant.dealership_name}: #{metric_label} is now overdue"
    when :gm_nudge
      "#{@tenant.dealership_name}: still no #{metric_label} for #{period_label}"
    else
      "#{@tenant.dealership_name}: action needed"
    end
  end

  def days_until_period_end
    tz = ActiveSupport::TimeZone[@tenant.time_zone] || ActiveSupport::TimeZone["UTC"]
    period_end = @prompt.scheduled_for.in_time_zone(tz).end_of_month.to_date
    today = Time.current.in_time_zone(tz).to_date
    [(period_end - today).to_i, 0].max
  end
end
