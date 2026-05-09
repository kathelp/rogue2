# Submissions::Capture
#
# Transactional creation of a Submission row + flip the prompt to
# :fulfilled + emit a submission.captured FlowEvent.
#
# Returns a Result struct so the controller can branch cleanly on
# success/idempotent-skip/validation-error.
module Submissions
  module Capture
    Result = Struct.new(:success, :submission, :error, keyword_init: true) do
      def success? = success
    end

    def self.call(prompt:, contact:, value:, notes: nil)
      if prompt.status_fulfilled?
        existing = ::Submission.where(submission_prompt: prompt).order(:submitted_at).first
        return Result.new(success: false, submission: existing, error: :already_submitted)
      end

      coerced_value = coerce_value(value)
      return Result.new(success: false, error: :invalid_value) if coerced_value.nil?

      submission = nil
      ApplicationRecord.transaction do
        period_start = period_starting_for(prompt)

        submission = ::Submission.create!(
          tenant: prompt.tenant,
          request: prompt.request,
          submission_prompt: prompt,
          submitted_by_contact: contact,
          value: coerced_value,
          notes: notes.presence,
          period_starting: period_start,
          submitted_at: Time.current
        )

        prompt.update!(status: :fulfilled, fulfilled_at: Time.current)

        FlowEvent.record!(
          event_type: "submission.captured",
          tenant: prompt.tenant,
          subject: submission,
          payload: {
            request_id: prompt.request_id,
            metric_key: prompt.request.metric_key,
            value: coerced_value.to_s,
            period_starting: period_start.iso8601
          }
        )
      end

      Result.new(success: true, submission: submission)
    rescue ActiveRecord::RecordInvalid
      Result.new(success: false, error: :invalid_value)
    end

    def self.coerce_value(value)
      return nil if value.nil? || value.to_s.strip.empty?

      f = Float(value, exception: false)
      return nil if f.nil? || f.negative?

      f
    end

    private_class_method :coerce_value

    def self.period_starting_for(prompt)
      tz = ActiveSupport::TimeZone[prompt.tenant.time_zone] || ActiveSupport::TimeZone["UTC"]
      prompt.scheduled_for.in_time_zone(tz).to_date.beginning_of_month
    end

    private_class_method :period_starting_for
  end
end
