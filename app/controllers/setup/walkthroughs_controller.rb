# Setup::WalkthroughsController
#
# 3-step invitee setup walkthrough at /setup/:signed_id.
# - Step 1 ("summary")  : assignment context (default).
# - Step 2 ("method")   : submission method picker (form / csv / api_post).
# - Step 3 ("done")     : confirmation + next due date.
#
# Resumable: the same signed_id returns to the current step until expiry
# (Contact#signed_id with purpose: :invitee_setup, 7-day expiry).
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

    case step_param
    when "method"
      :method_picker
    when "done"
      :done
    else
      :summary
    end
  end
end
