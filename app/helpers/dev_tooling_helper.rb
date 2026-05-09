# DevToolingHelper
#
# View helpers that exist solely to ease manual dev/QA testing.
# Every helper here MUST short-circuit to nil/false outside
# Rails.env.development? so production renders are unaffected.
module DevToolingHelper
  # Builds a URL into the Action Mailbox conductor's "new inbound email" form
  # with fields pre-populated from the supplied Mail::Message. Pasted as a
  # link at the bottom of every dev email by `app/views/layouts/mailer.*`.
  #
  # The conductor's stock new.html.erb reads `params[:from]`, `params[:to]`,
  # `params[:cc]`, `params[:in_reply_to]`, and `params[:subject]` as default
  # values, so no controller patching is needed.
  #
  # The "reply" semantics swap the original From/To: the recipient of the
  # outbound email becomes the From of the simulated inbound, and the original
  # From becomes the To. That gives a one-click way to fake an inbound reply
  # to whichever mailer you're looking at in letter-opener.
  #
  # Returns nil outside development, or when the message is missing the
  # headers needed to build a sensible URL.
  def dev_conductor_reply_url(message:)
    return nil unless Rails.env.development?
    return nil if message.nil?

    original_from = Array(message.from).first
    original_to   = Array(message.to).first
    return nil if original_from.blank? || original_to.blank?

    subject = message.subject.to_s
    subject = "Re: #{subject}" unless subject.start_with?(/Re:\s/i)

    msg_id = message.message_id
    in_reply_to = msg_id.present? ? "<#{msg_id}>" : nil

    new_rails_conductor_inbound_email_url(
      from:        original_to,
      to:          original_from,
      subject:     subject,
      in_reply_to: in_reply_to
    )
  end
end
