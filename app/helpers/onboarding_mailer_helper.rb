# OnboardingMailerHelper
#
# Helpers available inside OnboardingMailer views.
module OnboardingMailerHelper
  EASTERN = ActiveSupport::TimeZone["America/New_York"]

  # Returns a human-friendly string describing when the next question will arrive.
  # Used in in_thread_ack to set expectations with the GM.
  #
  # @param time [Time, nil]
  # @return [String]
  def humanize_next_question_at(time)
    return "shortly" if time.nil?

    delta = time - Time.current
    eastern_time = time.in_time_zone(EASTERN)

    if delta <= 18.hours
      hours = (delta / 1.hour).round
      hours <= 1 ? "in about an hour" : "in #{hours} hours"
    elsif delta <= 36.hours
      "tomorrow morning"
    else
      eastern_time.strftime("%A morning")
    end
  end
end
