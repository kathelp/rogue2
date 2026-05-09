class Onboarding::ConfirmationsController < ApplicationController
  def show
    @tenant = Tenant.find_by_gm_confirm_signed_id(params[:signed_id])

    if @tenant.nil?
      render(:invalid, status: :not_found)
      return
    end

    if @tenant.status_confirmed? || @tenant.status_active?
      render(:already_confirmed)
      return
    end

    if @tenant.confirm!
      FlowEvent.record!(
        event_type: "tenant.confirmed",
        tenant: @tenant,
        subject: @tenant
      )
      OnboardingFlow::EnqueueFirstQuestionJob.perform_later(tenant_id: @tenant.id)
      render(:show)
    else
      render(:invalid, status: :unprocessable_entity)
    end
  end

  def resend
    # Anti-enumeration per J5: always render the same success page regardless of whether the email matches.
    email = params[:email].to_s.strip.downcase
    tenant = Tenant.where(gm_email_normalized: email, status: "pending_confirm").first
    if tenant && rate_limit_ok?(email)
      OnboardingMailer.with(tenant: tenant).confirmation_email.deliver_later
      tenant.update!(confirmation_sent_at: Time.current)
      FlowEvent.record!(
        event_type: "tenant.confirmation_resent",
        tenant: tenant,
        subject: tenant
      )
    end
    # Always render the same response — anti-enumeration.
    render(:resend_sent)
  end

  private

  # Simple in-process rate limit for MVP: 3 sends per email per hour.
  # Rails.cache (Solid Cache backs it) with a 1-hour TTL.
  def rate_limit_ok?(email)
    key = "resend_rate_limit:#{email}"
    count = Rails.cache.fetch(key, expires_in: 1.hour) { 0 }
    if count >= 3
      false
    else
      Rails.cache.write(key, count + 1, expires_in: 1.hour)
      true
    end
  end
end
