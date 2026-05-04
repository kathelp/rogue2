# Submissions::FormsController
#
# Magic-link form for invited contacts to submit one data point per
# SubmissionPrompt. Renders one of four pages based on token + prompt
# state:
#   - valid token + prompt :sent → form
#   - valid token + prompt :fulfilled → already-submitted page (idempotent)
#   - expired/invalid token → expired page (404, no leakage)
#   - submitted with invalid value → form re-rendered with errors (422)
class Submissions::FormsController < ApplicationController
  before_action :load_prompt

  def show
    if @prompt.nil?
      render :expired, status: :not_found
      return
    end

    if @prompt.status_fulfilled?
      render :already_submitted
      return
    end

    render :show
  end

  def create
    if @prompt.nil?
      render :expired, status: :not_found
      return
    end

    if @prompt.status_fulfilled?
      render :already_submitted
      return
    end

    contact = @prompt.request.source.configured_by_contact

    result = Submissions::Capture.call(
      prompt:  @prompt,
      contact: contact,
      value:   submission_params[:value],
      notes:   submission_params[:notes]
    )

    if result.success?
      redirect_to submission_form_path(signed_id: params[:signed_id], submitted: 1)
    else
      flash.now[:alert] = error_message_for(result.error)
      @value_attempt = submission_params[:value]
      @notes_attempt = submission_params[:notes]
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_prompt
    @prompt = SubmissionPrompt.find_by_submission_form_signed_id(params[:signed_id])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    @prompt = nil
  end

  def submission_params
    params.fetch(:submission, {}).permit(:value, :notes)
  end

  def error_message_for(error)
    case error
    when :invalid_value     then "Please enter a non-negative number."
    when :already_submitted then "This submission has already been recorded."
    else                         "We couldn't save your submission. Please try again."
    end
  end
end
