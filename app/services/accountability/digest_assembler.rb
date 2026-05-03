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

      :pending_first_submission
    end
    private_class_method :status_for

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
