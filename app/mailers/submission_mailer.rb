class SubmissionMailer < ApplicationMailer
  include Threadable

  default from: "Rogue <hello@inbound.rogue.example>"

  # Sent when a SubmissionPrompt becomes due and the matching Source's
  # submission_method is :form. Carries a magic-link to the form.
  #
  # params[:prompt] - SubmissionPrompt
  def prompt_email
    @prompt    = params[:prompt]
    @tenant    = @prompt.tenant
    @request   = @prompt.request
    @source    = @request.source
    @contact   = @source.configured_by_contact
    @form_url  = submission_form_url(
      signed_id: @prompt.submission_form_signed_id(expires_in: 14.days)
    )

    mail(
      to:       @contact.email,
      from:     onboarding_address(@tenant),
      reply_to: onboarding_address(@tenant),
      subject:  prompt_subject
    )
  end

  # Sent when a SubmissionPrompt becomes due but the Source's
  # submission_method is :csv or :api_post — adapter generation is
  # FEAT-003 work, so the contact gets parked-state copy.
  #
  # params[:prompt] - SubmissionPrompt
  def adapter_pending_email
    @prompt   = params[:prompt]
    @tenant   = @prompt.tenant
    @request  = @prompt.request
    @source   = @request.source
    @contact  = @source.configured_by_contact
    @method   = @source.submission_method

    mail(
      to:      @contact.email,
      from:    onboarding_address(@tenant),
      subject: "#{@tenant.dealership_name}: your #{@method.to_s.upcase} adapter is on the way"
    )
  end

  private

  def prompt_subject
    "#{@tenant.dealership_name}: time to submit #{metric_label} for #{period_label}"
  end

  def metric_label
    @request.metric_key.to_s.tr("_", " ")
  end

  def period_label
    @prompt.scheduled_for.in_time_zone(@tenant.time_zone).strftime("%B %Y")
  end
end
