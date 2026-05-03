# DashboardsController
#
# Read-only placeholder dashboard at /dashboard/:signed_id (AC-NAV-2).
# Renders the same digest data as AccountabilityMailer#weekly_digest, plus
# the per-row Source / SubmissionPrompt summary. Rich UI is FEAT-003+.
class DashboardsController < ApplicationController
  def show
    @tenant = Tenant.find_by_dashboard_signed_id(params[:signed_id])

    if @tenant.nil?
      render :expired, status: :not_found
      return
    end

    @digest = Accountability::DigestAssembler.call(tenant: @tenant)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    @tenant = nil
    render :expired, status: :not_found
  end
end
