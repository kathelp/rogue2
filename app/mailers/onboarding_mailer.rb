require "ostruct"

class OnboardingMailer < ApplicationMailer
  include Threadable

  default from: "Rogue <hello@inbound.rogue.example>"

  # ---------------------------------------------------------------------------
  # In-thread acknowledgment — sent back to the GM after their reply is parsed.
  #
  # params[:tenant]           - Tenant
  # params[:intent]           - Symbol  (:assign | :self_assign | :skip | :unparseable | :clarification_response)
  # params[:primary_email]    - String | nil
  # params[:fallback_emails]  - Array<String>
  # params[:warnings]         - Array<String>  (serialized as strings)
  # params[:question]         - TenantQuestion | nil
  # params[:inbound_email]    - ActionMailbox::InboundEmail
  # params[:next_question_at] - Time | nil
  def in_thread_ack
    @tenant           = params[:tenant]
    @inbound_email    = params[:inbound_email]
    @next_question_at = params[:next_question_at]

    # Reconstruct a view-friendly struct from serializable params
    @parsed = OpenStruct.new( # rubocop:disable Style/OpenStructUse
      intent:          params[:intent]&.to_sym,
      primary_email:   params[:primary_email],
      fallback_emails: Array(params[:fallback_emails]),
      warnings:        Array(params[:warnings]).map(&:to_sym),
      question:        params[:question]
    )

    topic = @parsed.question&.prompt || "your reply"
    thread_with(@inbound_email.message_id)

    mail(
      to:       @tenant.gm_email,
      from:     onboarding_address(@tenant),
      reply_to: onboarding_address(@tenant),
      subject:  canonical_subject(@tenant, topic, reply: true)
    )
  end

  # ---------------------------------------------------------------------------
  # Sent to a non-GM sender who replies on the onboarding thread.
  #
  # params[:tenant]        - Tenant
  # params[:inbound_email] - ActionMailbox::InboundEmail
  def gm_only_thread_notice
    @tenant         = params[:tenant]
    @inbound_email  = params[:inbound_email]
    @sender_address = @inbound_email.mail.from.first

    thread_with(@inbound_email.message_id)

    mail(
      to:      @sender_address,
      from:    onboarding_address(@tenant),
      subject: "This thread is for #{@tenant.dealership_name}'s GM only"
    )
  end

  # ---------------------------------------------------------------------------
  # Asks the GM to clarify whether an unknown domain is internal or a vendor.
  #
  # params[:tenant]           - Tenant
  # params[:inbound_email]    - ActionMailbox::InboundEmail
  # params[:ambiguous_email]  - String  e.g. "alex@unknownvendor.com"
  # params[:ambiguous_domain] - String  e.g. "unknownvendor.com"
  def vendor_clarification
    @tenant           = params[:tenant]
    @inbound_email    = params[:inbound_email]
    @ambiguous_email  = params[:ambiguous_email]
    @ambiguous_domain = params[:ambiguous_domain]

    thread_with(@inbound_email.message_id)

    mail(
      to:       @tenant.gm_email,
      from:     onboarding_address(@tenant),
      reply_to: onboarding_address(@tenant),
      subject:  canonical_subject(
        @tenant,
        "is #{@ambiguous_domain} internal or a vendor?",
        reply: true
      )
    )
  end

  # ---------------------------------------------------------------------------

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
