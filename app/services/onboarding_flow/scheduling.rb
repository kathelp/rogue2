# OnboardingFlow::Scheduling
#
# Business-hours envelope service per user-journey decision J3.
# Questions (after the first) only deliver Mon-Fri 9:30am-6pm in the tenant's
# timezone. The first question email post-confirmation is exempt and sends
# immediately — see OnboardingFlow::EnqueueFirstQuestionJob.
#
# Usage:
#   target    = Time.current + tenant.next_question_delay_hours.hours
#   deliver_at = OnboardingFlow::Scheduling.next_business_window(
#                  after: target, time_zone: tenant.time_zone
#                )
#   OnboardingMailer.with(...).question_email.deliver_later(wait_until: deliver_at)
module OnboardingFlow
  module Scheduling
    # 9:30am expressed as decimal hours
    BUSINESS_HOURS_START = 9.5
    # 6:00pm expressed as decimal hours
    BUSINESS_HOURS_END = 18.0
    # Mon(1)..Fri(5) per Time#wday
    BUSINESS_DAYS = (1..5).to_a.freeze

    # Returns the next moment that falls within a business window at or after `after`.
    #
    # If `after` is already within a business window on a business day,
    # returns `after` unchanged.  Otherwise advances to the opening of
    # the next business window (9:30am in the given time_zone).
    #
    # @param after     [Time, ActiveSupport::TimeWithZone]
    # @param time_zone [String]  Rails/TZ database name, e.g. "America/New_York"
    # @return          [ActiveSupport::TimeWithZone]
    def self.next_business_window(after:, time_zone:)
      tz = ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone["UTC"]
      time = after.in_time_zone(tz)

      return time if in_business_window?(time, time_zone: time_zone)

      # Advance to the next business-window opening
      next_opening(time, tz)
    end

    # Returns true when `time` falls on a weekday between 9:30am and 6pm
    # (inclusive of 9:30am, exclusive of 6pm) in the given time_zone.
    #
    # @param time      [Time, ActiveSupport::TimeWithZone]
    # @param time_zone [String]
    # @return          [Boolean]
    def self.in_business_window?(time, time_zone:)
      tz = ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone["UTC"]
      local = time.in_time_zone(tz)

      return false unless BUSINESS_DAYS.include?(local.wday)

      decimal_hour = local.hour + local.min / 60.0
      decimal_hour >= BUSINESS_HOURS_START && decimal_hour < BUSINESS_HOURS_END
    end

    # ---------------------------------------------------------------------------
    private_class_method def self.next_opening(time, tz)
      # Start from the same calendar day at the open time
      candidate = beginning_of_day(time, tz) + hours_to_seconds(BUSINESS_HOURS_START)

      # If we're past the open today, move to the next day
      candidate += 1.day if candidate <= time

      # Advance past weekends
      candidate += 1.day until BUSINESS_DAYS.include?(candidate.wday)

      candidate
    end

    def self.beginning_of_day(time, tz)
      tz.local(time.year, time.month, time.day, 0, 0, 0)
    end

    private_class_method :beginning_of_day

    def self.hours_to_seconds(decimal_hours)
      (decimal_hours * 3600).to_i.seconds
    end

    private_class_method :hours_to_seconds
  end
end
