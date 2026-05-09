# CcOrdering is defined inline in OnboardingReplyParser (loaded first).
# This stub satisfies Zeitwerk's file-to-constant mapping requirement.
# rubocop:disable Lint/EmptyClass
class OnboardingReplyParser
  unless const_defined?(:CcOrdering, false)
    module CcOrdering
    end
  end
end
# rubocop:enable Lint/EmptyClass
