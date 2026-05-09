# OnboardingFlow::SubmissionPromptScheduler
#
# For each Request belonging to a Source, schedule the first SubmissionPrompt
# at the start of the next reporting period in the tenant's time zone.
# Idempotent: re-calling does not double-schedule pending prompts.
#
# Usage:
#   OnboardingFlow::SubmissionPromptScheduler.call(source: source)
module OnboardingFlow
  module SubmissionPromptScheduler
    def self.call(source:)
      tz = ActiveSupport::TimeZone[source.tenant.time_zone] || ActiveSupport::TimeZone["UTC"]
      now_local = Time.current.in_time_zone(tz)

      source.requests.map do |request|
        scheduled_for = next_period_start(cadence: request.cadence, now: now_local)

        SubmissionPrompt.find_or_create_by!(
          tenant: source.tenant,
          request: request,
          status: :pending
        ) do |prompt|
          prompt.scheduled_for = scheduled_for
        end
      end
    end

    # Next period start in the tenant's local time zone.
    def self.next_period_start(cadence:, now:)
      case cadence.to_s
      when "weekly"
        # Start of next ISO week (Monday)
        days_until_monday = ((1 - now.wday) % 7).then { |d| d.zero? ? 7 : d }
        now.beginning_of_day + days_until_monday.days
      when "monthly"
        (now + 1.month).beginning_of_month
      when "quarterly"
        next_quarter_start(now)
      when "semi_annual"
        next_half_year_start(now)
      when "annual"
        (now + 1.year).beginning_of_year
      else
        # Sensible default: 1 month out
        (now + 1.month).beginning_of_month
      end
    end

    private_class_method :next_period_start

    def self.next_quarter_start(now)
      # Q1=1-3, Q2=4-6, Q3=7-9, Q4=10-12
      next_q_first_month = ((now.month - 1) / 3 + 1) * 3 + 1
      if next_q_first_month > 12
        now.time_zone.local(now.year + 1, 1, 1)
      else
        now.time_zone.local(now.year, next_q_first_month, 1)
      end
    end

    private_class_method :next_quarter_start

    def self.next_half_year_start(now)
      next_h_first_month = now.month <= 6 ? 7 : 1
      year = now.month <= 6 ? now.year : now.year + 1
      now.time_zone.local(year, next_h_first_month, 1)
    end

    private_class_method :next_half_year_start
  end
end
