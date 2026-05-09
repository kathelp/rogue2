# OnboardingFlow::AdaptivePacing
#
# Computes the next question delivery gap based on GM responsiveness.
#
# Per user journey design J3:
#   - GM replies in < 1h  → next question in 12h
#   - GM replies in < 24h → next question in 24h
#   - GM replies in < 72h → next question in 48h
#   - GM silent ≥ 72h    → no question scheduled (returns nil)
module OnboardingFlow
  module AdaptivePacing
    # Returns wait duration as ActiveSupport::Duration, or nil when the GM
    # has been silent ≥ 72h (no question should be scheduled).
    #
    # @param question_sent_at  [Time, nil]  when the question email was dispatched
    # @param reply_received_at [Time]       when the GM's reply arrived
    # @return                  [ActiveSupport::Duration, nil]
    def self.next_wait(question_sent_at:, reply_received_at:)
      return 24.hours if question_sent_at.nil?

      # Guard against pathological clock skew (negative elapsed)
      elapsed = reply_received_at - question_sent_at
      elapsed = 0 if elapsed.negative?

      if elapsed <= 1.hour
        12.hours
      elsif elapsed <= 24.hours
        24.hours
      elsif elapsed <= 72.hours
        48.hours
      else
        # silence — do not schedule
        nil
      end
    end

    # Convenience method that returns the wait in hours (Numeric or nil).
    # Used as the `wait_hours:` argument to EnqueueNextQuestionJob.
    def self.next_wait_hours(question_sent_at:, reply_received_at:)
      duration = next_wait(question_sent_at: question_sent_at, reply_received_at: reply_received_at)
      duration&./(1.hour)
    end
  end
end
