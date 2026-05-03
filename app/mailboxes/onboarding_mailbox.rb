# OnboardingMailbox
#
# Processes inbound replies to the per-tenant onboarding address.
# Thin dispatcher: pulls tenant from the To: plus-address token,
# validates the sender is the GM, delegates parsing and artifact
# creation to service objects.
#
# Per architecture design A1 (plus-addressing) and algorithm design L1/L2.
class OnboardingMailbox < ApplicationMailbox
  before_processing :resolve_tenant
  before_processing :verify_gm_sender

  def process
    Current.tenant = @tenant

    parsed = OnboardingReplyParser.call(inbound_email: inbound_email, tenant: @tenant)

    # Persist parser metadata on the InboundEmail row
    inbound_email.update!(
      parser_intent:     parsed.intent.to_s,
      parser_confidence: parsed.confidence.to_s,
      parser_warnings:   parsed.warnings.map(&:to_s)
    )

    # Update last_gm_reply_at on every processed reply (all intents count)
    @tenant.update!(last_gm_reply_at: Time.current)

    FlowEvent.record!(
      event_type: "reply.parsed",
      tenant:     @tenant,
      subject:    inbound_email,
      payload:    {
        intent:     parsed.intent,
        confidence: parsed.confidence,
        warnings:   parsed.warnings
      }
    )

    case parsed.intent
    when :assign             then handle_assignment(parsed)
    when :self_assign        then handle_assignment(parsed)
    when :skip               then handle_skip(parsed)
    when :clarification_response then handle_clarification(parsed)
    when :unparseable        then handle_unparseable(parsed)
    end
  ensure
    Current.tenant = nil
  end

  # ---------------------------------------------------------------------------
  private
  # ---------------------------------------------------------------------------

  def resolve_tenant
    token = extract_token(mail.to.first.to_s)
    @tenant = Tenant.find_by(onboarding_token: token)

    if @tenant.nil?
      # Try In-Reply-To fallback for plus-stripped mail (A1 fallback route)
      @tenant = resolve_tenant_from_thread
    end

    bounced! if @tenant.nil?
  end

  def verify_gm_sender
    sender = mail.from.first.to_s.downcase.strip
    return if sender == @tenant.gm_email_normalized

    OnboardingMailer
      .with(tenant: @tenant, inbound_email: inbound_email)
      .gm_only_thread_notice
      .deliver_later

    FlowEvent.record!(
      event_type: "reply.rejected_non_gm_sender",
      tenant:     @tenant,
      subject:    inbound_email,
      payload:    { sender: sender }
    )

    bounced!
  end

  # ---------------------------------------------------------------------------
  # Intent handlers
  # ---------------------------------------------------------------------------

  def handle_assignment(parsed)
    primary_email   = parsed.primary_email
    fallback_emails = parsed.fallback_emails

    inference = VendorInferenceService.call(email: primary_email, tenant: @tenant)

    if inference.requires_clarification
      handle_unknown_vendor(parsed, primary_email)
      return
    end

    contact = Contact.find_or_create_for_email(
      tenant:         @tenant,
      email:          primary_email,
      classification: inference.classification,
      vendor:         inference.vendor
    )

    question = parsed.question || find_sent_or_skipped_question
    if question.nil?
      handle_unparseable(parsed)
      return
    end

    # If this is a revisit of a skipped question, mark it revisited
    if question.status_skipped?
      mark_question_revisited(question)
    end

    # Supersede any existing active responsibility for this question
    @tenant.responsibilities.where(tenant_question: question).status_active.update_all(status: :superseded)

    responsibility = Responsibility.create!(
      tenant:                  @tenant,
      tenant_question:         question,
      primary_contact:         contact,
      gm_self_assigned:        parsed.intent == :self_assign,
      fallback_contact_emails: fallback_emails,
      status:                  :active
    )

    # Create or find the Source for this (tenant, domain, responsibility_key) tuple
    source = find_or_create_source(question: question, vendor: inference.vendor)

    # Provision Request rows from the catalog metric list (one Request per metric).
    OnboardingFlow::RequestProvisioning.call(source: source, tenant_question: question)

    # Send setup email to the assigned non-GM contact.
    if parsed.intent == :assign
      OnboardingMailer
        .with(tenant: @tenant, contact: contact, responsibility: responsibility)
        .invitee_setup_email
        .deliver_later
    end

    # Mark the question answered
    question.update!(status: :answered, answered_at: Time.current)

    FlowEvent.record!(
      event_type: "responsibility.created",
      tenant:     @tenant,
      subject:    responsibility,
      payload:    {
        primary_email: primary_email,
        fallbacks:     fallback_emails,
        intent:        parsed.intent
      }
    )

    enqueue_next_question(question)
    send_in_thread_ack(parsed, next_question_at: next_question_delivery_time(question))
  end

  def handle_skip(parsed)
    question = parsed.question || find_sent_or_skipped_question
    if question.nil?
      handle_unparseable(parsed)
      return
    end

    # Record the skip (skipped_at lives on SkippedQuestion, not TenantQuestion)
    SkippedQuestion.find_or_create_by!(
      tenant:          @tenant,
      tenant_question: question
    ) do |sq|
      sq.skipped_at = Time.current
    end

    question.update!(status: :skipped)

    FlowEvent.record!(
      event_type: "question.skipped",
      tenant:     @tenant,
      subject:    question,
      payload:    { intent: :skip }
    )

    enqueue_next_question(question)
    send_in_thread_ack(parsed, next_question_at: next_question_delivery_time(question))
  end

  def handle_unparseable(parsed)
    FlowEvent.record!(
      event_type: "reply.unparseable",
      tenant:     @tenant,
      subject:    inbound_email,
      payload:    { warnings: parsed.warnings }
    )

    # Do NOT enqueue next question — question remains unanswered
    send_in_thread_ack(parsed, next_question_at: nil)
  end

  def handle_clarification(parsed)
    # Re-parse the body directly from the inbound email using the BodyExtractor
    body_result = OnboardingReplyParser::BodyExtractor.extract(inbound_email.mail)
    cleaned_body = body_result[:body].strip

    if cleaned_body.match?(/\Ainternal\s*[.!]?\s*\z/i)
      handle_clarification_internal(parsed)
    elsif (match = cleaned_body.match(/\Avendor:\s*(.+)\z/i))
      vendor_name = match[1].strip
      handle_clarification_vendor(parsed, vendor_name)
    else
      handle_unparseable(parsed)
    end
  end

  # ---------------------------------------------------------------------------
  # Clarification sub-handlers
  # ---------------------------------------------------------------------------

  def handle_clarification_internal(parsed)
    question = parsed.question || find_sent_or_skipped_question
    return handle_unparseable(parsed) if question.nil?

    ambiguous_email = extract_ambiguous_email_from_context(question)
    return handle_unparseable(parsed) if ambiguous_email.nil?

    reassigned_parsed = OnboardingReplyParser::ParsedReply.new(
      intent:          :assign,
      primary_email:   ambiguous_email,
      fallback_emails: [],
      question:        question,
      raw_excerpt:     parsed.raw_excerpt,
      confidence:      :high,
      warnings:        []
    )

    handle_assignment(reassigned_parsed)
  end

  def handle_clarification_vendor(parsed, vendor_name)
    question = parsed.question || find_sent_or_skipped_question
    return handle_unparseable(parsed) if question.nil?

    ambiguous_email = extract_ambiguous_email_from_context(question)
    return handle_unparseable(parsed) if ambiguous_email.nil?

    ambiguous_domain = ambiguous_email.split("@", 2).last

    vendor = Vendor.bootstrap!(
      name:              vendor_name,
      domains:           [ ambiguous_domain ],
      state:             :pending_review,
      source:            :clarification,
      created_by_tenant: @tenant
    )

    FlowEvent.record!(
      event_type: "vendor.bootstrap_from_clarification",
      tenant:     @tenant,
      subject:    vendor,
      payload:    { name: vendor_name, domain: ambiguous_domain }
    )

    reassigned_parsed = OnboardingReplyParser::ParsedReply.new(
      intent:          :assign,
      primary_email:   ambiguous_email,
      fallback_emails: [],
      question:        question,
      raw_excerpt:     parsed.raw_excerpt,
      confidence:      :high,
      warnings:        []
    )

    handle_assignment(reassigned_parsed)
  end

  def handle_unknown_vendor(parsed, ambiguous_email)
    ambiguous_domain = ambiguous_email.to_s.split("@", 2).last

    FlowEvent.record!(
      event_type: "vendor.clarification_requested",
      tenant:     @tenant,
      subject:    inbound_email,
      payload:    {
        ambiguous_email:  ambiguous_email,
        ambiguous_domain: ambiguous_domain,
        question_id:      parsed.question&.id
      }
    )

    OnboardingMailer
      .with(
        tenant:           @tenant,
        inbound_email:    inbound_email,
        ambiguous_email:  ambiguous_email,
        ambiguous_domain: ambiguous_domain
      )
      .vendor_clarification
      .deliver_later
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def extract_token(address)
    address.to_s.split("@").first.sub(/\Aonboarding\+/i, "")
  end

  def resolve_tenant_from_thread
    candidate_ids = Array(mail.in_reply_to).flatten.compact + Array(mail.references).flatten.compact
    return nil if candidate_ids.empty?

    normalized = candidate_ids.map { |id| id.to_s.delete("<>").strip }
    question   = TenantQuestion.where(outbound_message_id: normalized).first
    question&.tenant
  end

  # Find the most relevant question to answer: first try sent questions,
  # then fall back to skipped questions (for revisits). Returns nil if
  # there's ambiguity (multiple candidates).
  def find_sent_or_skipped_question
    sent_questions = @tenant.tenant_questions.status_sent.order(:position)
    return sent_questions.first if sent_questions.count == 1

    if sent_questions.empty?
      skipped = @tenant.tenant_questions.status_skipped.order(:position)
      return skipped.first if skipped.count == 1
    end

    nil
  end

  def mark_question_revisited(question)
    sq = SkippedQuestion.where(tenant: @tenant, tenant_question: question).first
    sq&.update!(revisited_at: Time.current)

    FlowEvent.record!(
      event_type: "question.revisited",
      tenant:     @tenant,
      subject:    question,
      payload:    {}
    )
  end

  def find_or_create_source(question:, vendor:)
    @tenant.sources.find_or_create_by!(
      domain:             question.domain,
      responsibility_key: question.key
    ) do |s|
      s.vendor = vendor
    end
  end

  def enqueue_next_question(answered_question)
    wait_hours = OnboardingFlow::AdaptivePacing.next_wait_hours(
      question_sent_at:  answered_question&.sent_at,
      reply_received_at: Time.current
    )

    return if wait_hours.nil?

    OnboardingFlow::EnqueueNextQuestionJob
      .set(wait: wait_hours.hours)
      .perform_later(tenant_id: @tenant.id, wait_hours: wait_hours)
  end

  def next_question_delivery_time(answered_question)
    wait_hours = OnboardingFlow::AdaptivePacing.next_wait_hours(
      question_sent_at:  answered_question&.sent_at,
      reply_received_at: Time.current
    )

    return nil if wait_hours.nil?

    target = Time.current + wait_hours.hours
    OnboardingFlow::Scheduling.next_business_window(
      after:     target,
      time_zone: @tenant.time_zone
    )
  end

  def extract_ambiguous_email_from_context(question)
    event = FlowEvent
      .where(tenant: @tenant, event_type: "vendor.clarification_requested")
      .where("payload->>'question_id' = ?", question.id.to_s)
      .order(occurred_at: :desc)
      .first
    event&.payload&.dig("ambiguous_email")
  end

  # Sends the in_thread_ack mailer. Uses serializable params (no Structs).
  def send_in_thread_ack(parsed, next_question_at:)
    OnboardingMailer
      .with(
        tenant:           @tenant,
        intent:           parsed.intent.to_s,
        primary_email:    parsed.primary_email,
        fallback_emails:  parsed.fallback_emails,
        warnings:         parsed.warnings.map(&:to_s),
        question:         parsed.question,
        inbound_email:    inbound_email,
        next_question_at: next_question_at
      )
      .in_thread_ack
      .deliver_later
  end
end
