# SkipDetector is defined inline in OnboardingReplyParser (loaded first).
# This stub satisfies Zeitwerk's file-to-constant mapping requirement.
class OnboardingReplyParser
  unless const_defined?(:SkipDetector, false)
    module SkipDetector
    end
  end
end
