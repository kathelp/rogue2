class Tenant::Seeder
  Result = Struct.new(:success?, :tenant, :errors, keyword_init: true)

  def self.call(dealership_name:, gm_name:, gm_email:)
    new(dealership_name:, gm_name:, gm_email:).call
  end

  def initialize(dealership_name:, gm_name:, gm_email:)
    @dealership_name = dealership_name
    @gm_name = gm_name
    @gm_email = gm_email
  end

  def call
    tenant = Tenant.new(
      dealership_name: @dealership_name,
      gm_name: @gm_name,
      gm_email: @gm_email,
      status: "pending_confirm",
      confirmation_sent_at: Time.current
    )

    if tenant.save
      OnboardingMailer.with(tenant: tenant).confirmation_email.deliver_later
      FlowEvent.record!(
        event_type: "tenant.seeded",
        tenant: tenant,
        subject: tenant,
        payload: {
          dealership_name: tenant.dealership_name,
          gm_email: tenant.gm_email_normalized
        }
      )
      Result.new(success?: true, tenant: tenant, errors: nil)
    else
      Result.new(success?: false, tenant: tenant, errors: tenant.errors.full_messages)
    end
  end
end
