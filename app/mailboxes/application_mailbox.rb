class ApplicationMailbox < ActionMailbox::Base
  routing(/^onboarding\+/i => :onboarding)
  # fallback for mail filters that strip plus-addressing
  routing(/^onboarding@/i => :onboarding)
end
