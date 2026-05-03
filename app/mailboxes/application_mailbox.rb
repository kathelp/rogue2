class ApplicationMailbox < ActionMailbox::Base
  routing(/^onboarding\+/i => :onboarding)
  routing(/^onboarding@/i  => :onboarding) # fallback for mail filters that strip plus-addressing
end
