# Setup::Completion
#
# Finishes the invitee setup walkthrough:
#   1. Validates and persists the chosen submission_method on the Source.
#   2. Provisions Request rows from the question catalog's metric list.
#   3. Schedules the first SubmissionPrompt for each Request.
#   4. Records a FlowEvent.
#
# Returns a Result struct so the controller can branch cleanly on success/failure.
module Setup
  module Completion
    Result = Struct.new(:success, :source, :error, keyword_init: true) do
      def success? = success
    end

    VALID_METHODS = %w[form csv api_post].freeze

    def self.call(source:, contact:, submission_method:)
      method = submission_method.to_s
      unless VALID_METHODS.include?(method)
        return Result.new(success: false, source: source, error: :invalid_submission_method)
      end

      ApplicationRecord.transaction do
        source.update!(
          submission_method:        method,
          configured_at:            Time.current,
          configured_by_contact_id: contact.id
        )

        question = TenantQuestion
          .where(tenant: source.tenant, key: source.responsibility_key)
          .order(catalog_version: :desc)
          .first
        OnboardingFlow::RequestProvisioning.call(source: source, tenant_question: question) if question
        OnboardingFlow::SubmissionPromptScheduler.call(source: source)

        FlowEvent.record!(
          event_type: "source.configured",
          tenant:     source.tenant,
          subject:    source,
          payload:    {
            submission_method: method,
            contact_id:        contact.id
          }
        )
      end

      Result.new(success: true, source: source)
    end
  end
end
