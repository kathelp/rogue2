class OnboardingMailer < ApplicationMailer
  default from: "Rogue <hello@inbound.rogue.example>"

  def confirmation_email
    @tenant = params[:tenant]
    @confirm_url = onboarding_confirmation_url(
      signed_id: @tenant.gm_confirm_signed_id(expires_in: 72.hours)
    )
    mail(
      to: @tenant.gm_email,
      subject: "Welcome to Rogue — confirm to begin"
    )
  end
end
