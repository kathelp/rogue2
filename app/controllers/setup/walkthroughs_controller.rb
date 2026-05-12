# Setup::WalkthroughsController
#
# 4-step invitee setup walkthrough at /setup/:signed_id.
# - Step 1 ("identity") : the contact fills in first/last/phone (unverified
#                         contacts only — see Contact#verified?). Verified
#                         contacts skip this step.
# - Step 2 ("summary")  : assignment context (default landing for verified).
# - Step 3 ("method")   : submission method picker (form / csv / api_post).
# - Step 4 ("done")     : confirmation + next due date.
#
# Resumable: the same signed_id returns to the current step until expiry
# (Contact#invitee_setup_signed_id with purpose: :invitee_setup, 7-day expiry).
class Setup::WalkthroughsController < ApplicationController
  before_action :load_contact

  def show
    if @contact.nil?
      render(:expired, status: :not_found)
      return
    end

    @responsibility = current_responsibility
    @source = current_source

    render(template_for_step(params[:step]))
  end

  def update
    if @contact.nil?
      render(:expired, status: :not_found)
      return
    end

    @responsibility = current_responsibility
    @source = current_source

    if params.key?(:contact)
      handle_identity_update
    else
      handle_source_update
    end
  end

  private

  def load_contact
    @contact = Contact.find_by_invitee_setup_signed_id(params[:signed_id])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    @contact = nil
  end

  # Most recently created active Responsibility for this contact.
  # MVP: contacts typically have one assignment; multi-assignment will get
  # a per-responsibility token in a follow-up.
  def current_responsibility
    @contact.responsibilities.where(status: :active).order(created_at: :desc).first
  end

  def current_source
    return nil if @responsibility.nil?

    @responsibility.tenant.sources.find_by(
      domain: @responsibility.tenant_question.domain,
      responsibility_key: @responsibility.tenant_question.key
    )
  end

  def template_for_step(step_param)
    return :done if @source && @source.submission_method.present?
    return :identity if @contact.unverified?

    case step_param
    when "method"
      :method_picker
    when "done"
      :done
    else
      :summary
    end
  end

  def handle_source_update
    method = params.dig(:source, :submission_method).to_s

    result = Setup::Completion.call(
      source: @source,
      contact: @contact,
      submission_method: method
    )

    if result.success?
      redirect_to(setup_walkthrough_path(signed_id: params[:signed_id], step: "done"))
    else
      flash.now[:alert] = "Please pick a submission method."
      render(:method_picker, status: :unprocessable_entity)
    end
  end

  def handle_identity_update
    permitted = params.require(:contact).permit(:first_name, :last_name, :phone)
    phone_result = Contacts::PhoneNormalizer.call(permitted[:phone])

    @errors = identity_errors_for(permitted, phone_result)

    if @errors.any?
      # Repopulate first/last from the submitted values; phone is preserved
      # separately in @phone_attempt because the column is encrypted and
      # cannot accept the raw unparsed string.
      @contact.assign_attributes(
        first_name: permitted[:first_name],
        last_name: permitted[:last_name]
      )
      @phone_attempt = permitted[:phone]
      render(:identity, status: :unprocessable_entity)
      return
    end

    ActiveRecord::Base.transaction do
      @contact.update!(
        first_name: permitted[:first_name],
        last_name: permitted[:last_name],
        phone: phone_result.normalized
      )
      FlowEvent.record!(
        event_type: "contact.verified",
        tenant: @contact.tenant,
        subject: @contact,
        actor: @contact
      )
    end

    redirect_to(setup_walkthrough_path(signed_id: params[:signed_id], step: "summary"))
  end

  def identity_errors_for(permitted, phone_result)
    errors = {}
    errors[:first_name] = "First name can't be blank" if permitted[:first_name].blank?
    errors[:last_name] = "Last name can't be blank" if permitted[:last_name].blank?

    if permitted[:phone].blank?
      errors[:phone] = "Mobile phone can't be blank"
    elsif !phone_result.valid?
      errors[:phone] = "Please enter a valid US mobile number (10 digits)"
    end

    errors
  end
end
