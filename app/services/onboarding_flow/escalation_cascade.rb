# OnboardingFlow::EscalationCascade
#
# Pure-function severity classifier. Given a SubmissionPrompt and the
# current time, returns a NextAction value object describing the next
# escalation step (or nil if it's not yet time).
#
# The FlowEvent log is the single source of truth for "what's been
# escalated already" — the cascade reads it but never writes. The
# detector job is responsible for emitting FlowEvents and queuing
# mailers based on this classifier's output.
#
# Severity ladder (per FEAT-004 spec):
#   nil                  → before due_soon window opens
#   :due_soon            → 3 days before period_end
#   :overdue             → 3 days past period_end
#   :fallback_fanout(N)  → 4 days after the previous fallback fanout (or overdue)
#   :gm_nudge            → 5 days after the last fallback (or after overdue if no fallbacks)
#   nil                  → GM nudge already fired (one-shot per period)
module OnboardingFlow
  module EscalationCascade
    DUE_SOON_GRACE_DAYS = 3
    OVERDUE_GRACE_DAYS = 3
    FALLBACK_GRACE_DAYS = 4
    GM_GRACE_DAYS = 5

    NextAction = Struct.new(
      # :due_soon | :overdue | :fallback_fanout | :gm_nudge
      :severity,
      # String — who to mail
      :recipient_email,
      # Hash — extra context (e.g., fallback_index)
      :payload,
      keyword_init: true
    )

    # Returns NextAction or nil.
    def self.next_action_for(prompt:, now: Time.current)
      tenant = prompt.tenant
      tz = ActiveSupport::TimeZone[tenant.time_zone] || ActiveSupport::TimeZone["UTC"]

      period_end_date = period_end_date_for(prompt, tz)
      now_date = now.in_time_zone(tz).to_date
      events = escalation_events_for(prompt)

      # GM nudge already happened: one-shot, done.
      return nil if events.any? { |e| e.event_type == "escalation.gm_nudge" }

      due_soon_event = events.find { |e| e.event_type == "escalation.due_soon" }
      overdue_event = events.find { |e| e.event_type == "escalation.overdue" }
      fallback_events = events
        .select { |e| e.event_type == "escalation.fallback_fanout" }
        .sort_by(&:occurred_at)

      due_soon_grace = tenant.escalation_due_soon_grace_days || DUE_SOON_GRACE_DAYS
      overdue_grace = tenant.escalation_overdue_grace_days || OVERDUE_GRACE_DAYS
      fallback_grace = tenant.escalation_fallback_grace_days || FALLBACK_GRACE_DAYS
      gm_grace = tenant.escalation_gm_grace_days || GM_GRACE_DAYS

      due_soon_open_date = period_end_date - due_soon_grace
      overdue_open_date = period_end_date + overdue_grace

      # Step 1: due_soon (calendar-day threshold)
      if due_soon_event.nil?
        return nil if now_date < due_soon_open_date

        return NextAction.new(
          severity: :due_soon,
          recipient_email: primary_email_for(prompt),
          payload: {period_end: period_end_date.iso8601}
        )
      end

      # Step 2: overdue (calendar-day threshold)
      if overdue_event.nil?
        return nil if now_date < overdue_open_date

        return NextAction.new(
          severity: :overdue,
          recipient_email: primary_email_for(prompt),
          payload: {period_end: period_end_date.iso8601}
        )
      end

      # Step 3: fallback fan-out (in order)
      fallbacks = fallback_emails_for(prompt)
      next_fallback_index = fallback_events.length
      previous_event = fallback_events.last || overdue_event

      if next_fallback_index < fallbacks.length
        threshold = previous_event.occurred_at + fallback_grace.days
        return nil if now < threshold

        return NextAction.new(
          severity: :fallback_fanout,
          recipient_email: fallbacks[next_fallback_index],
          payload: {
            fallback_index: next_fallback_index,
            fallback_email: fallbacks[next_fallback_index]
          }
        )
      end

      # Step 4: gm_nudge (after fallbacks exhausted, or directly after overdue when fallbacks empty)
      threshold = previous_event.occurred_at + gm_grace.days
      return nil if now < threshold

      NextAction.new(
        severity: :gm_nudge,
        recipient_email: tenant.gm_email,
        payload: {
          period_end: period_end_date.iso8601,
          fallback_chain: fallbacks,
          primary_email: responsibility_primary_email_for(prompt)
        }
      )
    end

    # ---------------------------------------------------------------------------

    def self.escalation_events_for(prompt)
      FlowEvent
        .where(subject_type: "SubmissionPrompt", subject_id: prompt.id)
        .where("event_type LIKE ?", "escalation.%")
        .order(:occurred_at)
        .to_a
    end

    private_class_method :escalation_events_for

    # Last day of the reporting period in tenant TZ as a Date. Monthly
    # cadence at MVP — last day of the month containing scheduled_for.
    def self.period_end_date_for(prompt, tz)
      scheduled_local = prompt.scheduled_for.in_time_zone(tz)
      scheduled_local.end_of_month.to_date
    end

    private_class_method :period_end_date_for

    def self.primary_email_for(prompt)
      contact = prompt.request.source.configured_by_contact
      contact&.email || prompt.tenant.gm_email
    end

    private_class_method :primary_email_for

    def self.fallback_emails_for(prompt)
      Array(active_responsibility_for(prompt)&.fallback_contact_emails)
    end

    private_class_method :fallback_emails_for

    # Email of the responsibility's primary_contact — i.e., the person the GM
    # said is on the hook, NOT the source.configured_by_contact (which is
    # whoever clicked through setup; usually the same but not always).
    def self.responsibility_primary_email_for(prompt)
      active_responsibility_for(prompt)&.primary_contact&.email
    end

    private_class_method :responsibility_primary_email_for

    def self.active_responsibility_for(prompt)
      prompt
        .tenant
        .responsibilities
        .where(status: :active)
        .joins(:tenant_question)
        .where(tenant_questions: {key: prompt.request.source.responsibility_key})
        .order(created_at: :desc)
        .first
    end

    private_class_method :active_responsibility_for
  end
end
