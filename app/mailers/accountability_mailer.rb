class AccountabilityMailer < ApplicationMailer
  default from: "Rogue <hello@inbound.rogue.example>"

  helper AccountabilityHelper

  # Weekly accountability digest (AC-HAPPY-8 / AC-ASYNC-3 / AC-NAV-2).
  #
  # params[:tenant] - Tenant
  def weekly_digest
    @tenant = params[:tenant]
    @digest = Accountability::DigestAssembler.call(tenant: @tenant)
    @dashboard_url = dashboard_url(
      signed_id: @tenant.dashboard_signed_id(expires_in: 8.days)
    )

    mail(
      to: @tenant.gm_email,
      subject: "#{@tenant.dealership_name} — weekly accountability digest"
    )
  end
end
