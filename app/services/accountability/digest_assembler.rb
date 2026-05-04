# Accountability::DigestAssembler
#
# Computes the per-tenant data the weekly digest needs to render.
# Returns a Digest value object with one Row per active Responsibility.
# Empty tenants (no active responsibilities) get an empty rows array
# AND `empty?` returns true so the mailer renders the empty-state copy.
#
# Per AC-HAPPY-8 + AC-ASYNC-3.
module Accountability
  module DigestAssembler
    Row = Struct.new(
      :responsibility,
      :primary_email,
      :status,         # :pending_setup | :pending_first_submission | :on_time | :late | :overdue
      :next_due_at,    # Time | nil
      keyword_init: true
    )

    Digest = Struct.new(:rows, keyword_init: true) do
      def empty? = rows.empty?
    end

    def self.call(tenant:)
      responsibilities = tenant.responsibilities
                               .where(status: :active)
                               .includes(:tenant_question, :primary_contact)
                               .order(created_at: :asc)

      rows = responsibilities.map { |r| build_row(r) }
      Digest.new(rows: rows)
    end

    def self.build_row(responsibility)
      tenant   = responsibility.tenant
      question = responsibility.tenant_question
      source   = tenant.sources.find_by(domain: question.domain, responsibility_key: question.key)

      Row.new(
        responsibility: responsibility,
        primary_email:  responsibility.primary_email,
        status:         status_for(source),
        next_due_at:    next_due_at_for(tenant, source)
      )
    end
    private_class_method :build_row

    def self.status_for(source)
      return :pending_setup if source.nil? || source.submission_method.blank?
      return :on_time if any_current_period_submission?(source)

      escalation_status = escalation_status_for(source) and return escalation_status

      :pending_first_submission
    end
    private_class_method :status_for

    # Reads the FlowEvent log to surface late/overdue states for a Source whose
    # current expected period has passed without a Submission. :overdue when
    # any escalation.fallback_fanout or escalation.gm_nudge has fired;
    # :late when the period has passed but no escalation has fanned out yet.
    # Returns nil when no escalation surface applies (e.g., period not yet over).
    def self.escalation_status_for(source)
      tz = ActiveSupport::TimeZone[source.tenant.time_zone] || ActiveSupport::TimeZone["UTC"]
      now_local = Time.current.in_time_zone(tz)

      sent_prompt = SubmissionPrompt
        .joins(:request)
        .where(tenant: source.tenant, requests: { source_id: source.id }, status: :sent)
        .order(scheduled_for: :desc)
        .first

      return nil if sent_prompt.nil?

      period_end = sent_prompt.scheduled_for.in_time_zone(tz).end_of_month
      return nil if now_local <= period_end

      escalation_events = FlowEvent
        .where(subject_type: "SubmissionPrompt", subject_id: sent_prompt.id)
        .where("event_type LIKE ?", "escalation.%")

      return :overdue if escalation_events.where(event_type: %w[escalation.fallback_fanout escalation.gm_nudge]).exists?

      :late
    end
    private_class_method :escalation_status_for

    def self.any_current_period_submission?(source)
      tz = ActiveSupport::TimeZone[source.tenant.time_zone] || ActiveSupport::TimeZone["UTC"]
      current_period_start = Time.current.in_time_zone(tz).to_date.beginning_of_month

      Submission
        .joins(:request)
        .where(tenant: source.tenant, requests: { source_id: source.id })
        .where(period_starting: current_period_start)
        .exists?
    end
    private_class_method :any_current_period_submission?

    def self.next_due_at_for(tenant, source)
      return nil if source.nil?

      SubmissionPrompt
        .joins(:request)
        .where(tenant: tenant, requests: { source_id: source.id }, status: :pending)
        .order(:scheduled_for)
        .first
        &.scheduled_for
    end
    private_class_method :next_due_at_for
  end
end
