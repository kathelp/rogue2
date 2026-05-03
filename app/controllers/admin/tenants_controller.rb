class Admin::TenantsController < Admin::BaseController
  def new
    @tenant = Tenant.new
  end

  def create
    result = Tenant::Seeder.call(**tenant_params.to_h.symbolize_keys)
    if result.success?
      redirect_to admin_tenant_path(result.tenant),
        notice: "Seeded #{result.tenant.dealership_name} — confirmation email queued for #{result.tenant.gm_email}."
    else
      @tenant = result.tenant
      flash.now[:alert] = result.errors.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @tenant = Tenant.find(params[:id])
  end

  def resend_confirmation
    tenant = Tenant.find(params[:id])
    if tenant.status_confirmed? || tenant.status_active?
      redirect_to admin_tenant_path(tenant), alert: "#{tenant.dealership_name} is already confirmed."
    else
      OnboardingMailer.with(tenant: tenant).confirmation_email.deliver_later
      tenant.update!(confirmation_sent_at: Time.current)
      FlowEvent.record!(
        event_type: "tenant.confirmation_resent",
        tenant: tenant,
        subject: tenant
      )
      redirect_to admin_tenant_path(tenant),
        notice: "Confirmation email re-queued for #{tenant.gm_email}."
    end
  end

  private

  def tenant_params
    params.require(:tenant).permit(:dealership_name, :gm_name, :gm_email)
  end
end
