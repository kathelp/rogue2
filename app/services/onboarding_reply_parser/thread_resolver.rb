# ThreadResolver is defined inline in OnboardingReplyParser (loaded first).
# This stub satisfies Zeitwerk's file-to-constant mapping requirement.
class OnboardingReplyParser
  unless const_defined?(:ThreadResolver, false)
    module ThreadResolver
    end
  end
end
