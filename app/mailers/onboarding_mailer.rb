class OnboardingMailer < ApplicationMailer
  include Threadable

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

  # Sends the next onboarding question to the GM.
  #
  # params[:tenant]          — the Tenant record
  # params[:tenant_question] — the TenantQuestion to ask
  # params[:message_id]      — pre-generated RFC 2822 Message-ID (optional).
  #                            When provided, the header is set explicitly so
  #                            the job can persist it before delivery.
  def question_email
    @tenant          = params[:tenant]
    @question        = params[:tenant_question]
    message_id_param = params[:message_id]

    m = mail(
      to:         @tenant.gm_email,
      from:       onboarding_address(@tenant),
      reply_to:   onboarding_address(@tenant),
      subject:    canonical_subject(@tenant, @question.prompt)
    ) do |format|
      format.html
      format.text
    end

    # Set the explicit Message-ID if the caller supplied one, so inbound
    # In-Reply-To resolution can look it up before delivery completes.
    if message_id_param.present?
      # Mail gem exposes message_id= on the Mail::Message object
      m.message_id = message_id_param
    end

    m
  end
end
