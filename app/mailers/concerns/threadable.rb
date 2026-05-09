# Threadable — mailer concern for outbound threading and per-tenant onboarding addressing.
#
# Per algorithm design L2.a/b/c:
# - Sets In-Reply-To and References headers on outbound mail when threading
#   to a parent inbound message.
# - Forces canonical subject prefix `[Dealership Onboarding] <topic>`.
# - Exposes onboarding_address helper for From: / Reply-To:.
#
# Usage in a mailer action:
#
#   include Threadable   # (via OnboardingMailer)
#
#   def question_email
#     @tenant = params[:tenant]
#     @question = params[:tenant_question]
#     mail(
#       to: @tenant.gm_email,
#       from: onboarding_address(@tenant),
#       reply_to: onboarding_address(@tenant),
#       subject: canonical_subject(@tenant, @question.prompt)
#     )
#   end
#
#   def in_thread_ack
#     @inbound = params[:inbound_email]
#     thread_with(@inbound.message_id)
#     mail(...)
#   end
module Threadable
  extend ActiveSupport::Concern

  private

  # Builds the per-tenant onboarding From:/Reply-To: address.
  # Domain comes from credentials (never hardcoded — 12-Factor).
  def onboarding_address(tenant)
    domain = Rails.application.credentials.dig(:inbound_email_domain) || "inbound.rogue.example"
    "#{tenant.dealership_name} Onboarding <onboarding+#{tenant.onboarding_token}@#{domain}>"
  end

  # Builds the canonical subject line for onboarding mail.
  # reply: true prefixes "Re: " (for in-thread acks).
  def canonical_subject(tenant, topic, reply: false)
    base = "[#{tenant.dealership_name} Onboarding] #{topic}"
    reply ? "Re: #{base}" : base
  end

  # Sets In-Reply-To and References headers so that outbound mail threads
  # inside the GM's existing conversation.
  #
  # parent_message_id — the RFC 2822 Message-ID of the parent message,
  # e.g., "<abc123@mail.gmail.com>". Angle brackets are optional; this
  # method normalises them.
  def thread_with(parent_message_id)
    return if parent_message_id.blank?

    mid = ensure_angle_brackets(parent_message_id.to_s)
    headers["In-Reply-To"] = mid
    headers["References"] = mid
  end

  private

  def ensure_angle_brackets(id)
    id = id.strip
    id = "<#{id}" unless id.start_with?("<")
    id = "#{id}>" unless id.end_with?(">")
    id
  end
end
