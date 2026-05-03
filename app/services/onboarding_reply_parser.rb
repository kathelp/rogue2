require "email_reply_trimmer"

# OnboardingReplyParser
#
# Pure service: classifies an inbound GM reply into a typed ParsedReply value
# object. Mutates nothing. Never raises for malformed mail — malformed mail
# flows through as :unparseable.
#
# Usage:
#   parsed = OnboardingReplyParser.call(inbound_email: inbound_email, tenant: tenant)
#   parsed.intent      # => :assign | :self_assign | :skip | :unparseable | :clarification_response
#   parsed.primary_email
#   parsed.fallback_emails
#
# Per algorithm design L1.
class OnboardingReplyParser
  # Typed result value object.
  ParsedReply = Struct.new(
    :intent,           # :assign | :self_assign | :skip | :unparseable | :clarification_response
    :primary_email,    # String? (normalized lowercase)
    :fallback_emails,  # Array<String> (normalized, ordered)
    :question,         # TenantQuestion | nil
    :raw_excerpt,      # String — meaningful body slice for audit (≤ 4 KB)
    :confidence,       # :high | :medium | :low
    :warnings,         # Array<Symbol>
    keyword_init: true
  )

  # ---------------------------------------------------------------------------
  # CC Ordering
  # Per L1.a: trust wire order; emit :cc_order_uncertain for known re-orderers.
  # ---------------------------------------------------------------------------
  module CcOrdering
    REORDERING_CLIENTS = [
      /Microsoft Office Outlook Web/i,
      /Outlook-iOS/i
    ].freeze

    def self.normalize(mail)
      addresses = extract_addresses(mail)
      warnings  = reorderer?(mail) ? [ :cc_order_uncertain ] : []
      [ addresses, warnings ]
    end

    def self.extract_addresses(mail)
      raw_cc = mail.cc
      return [] if raw_cc.blank?

      addrs = case raw_cc
      when String then raw_cc.split(",")
      when Array  then raw_cc
      else        Array(raw_cc)
      end

      addrs.map { |a| normalize_address(a) }.compact.reject(&:blank?)
    end
    private_class_method :extract_addresses

    def self.normalize_address(addr)
      raw = if addr.respond_to?(:address)
              addr.address
      else
              addr.to_s
      end
      raw&.strip&.downcase.presence
    end
    private_class_method :normalize_address

    def self.reorderer?(mail)
      user_agent = (
        mail.header[:user_agent]&.to_s ||
        mail.header["X-Mailer"]&.to_s ||
        ""
      )
      REORDERING_CLIENTS.any? { |re| user_agent.match?(re) }
    end
    private_class_method :reorderer?
  end

  # ---------------------------------------------------------------------------
  # Body Extractor
  # Per L1.b and L1.d: EmailReplyTrimmer + Nokogiri quote stripping.
  # ---------------------------------------------------------------------------
  module BodyExtractor
    SIGNATURE_PATTERNS = [
      /^--\s*$/,
      /^-{3,}\s*$/,
      /^Sent from my (iPhone|iPad|Android)/i,
      /^Get Outlook for (iOS|Android)/i,
      /^Sent via the Samsung Galaxy/i,
      /^_{3,}\s*$/
    ].freeze

    def self.extract(mail)
      plain = pick_plain_part(mail)
      html  = pick_html_part(mail)
      warnings = []

      raw_body =
        if plain.present?
          plain
        elsif html.present?
          warnings << :html_only_reply
          strip_html_to_text(html)
        else
          warnings << :empty_body
          return { body: "", confidence: :low, warnings: warnings }
        end

      trimmed = EmailReplyTrimmer.trim(raw_body)

      # Strip signatures beyond what EmailReplyTrimmer catches
      body_lines = trimmed.lines
      sig_idx = body_lines.find_index { |line| SIGNATURE_PATTERNS.any? { |p| line.match?(p) } }
      cleaned = sig_idx ? body_lines[0...sig_idx].join : trimmed
      cleaned = cleaned.strip

      confidence = assess_confidence(raw: raw_body, trimmed: trimmed, cleaned: cleaned)

      if plain.present? && html.present?
        html_text    = strip_html_to_text(html)
        html_trimmed = EmailReplyTrimmer.trim(html_text)
        if normalize_for_compare(html_trimmed) != normalize_for_compare(trimmed)
          warnings << :html_plain_diverged
        end
      end

      { body: cleaned, confidence: confidence, warnings: warnings }
    end

    def self.pick_plain_part(mail)
      if mail.parts.empty? && mail.content_type&.start_with?("text/plain")
        return mail.body.decoded
      end
      # Multipart with no explicit content-type also falls here
      if mail.parts.empty? && mail.content_type.blank?
        return mail.body.decoded
      end

      mail.text_part&.decoded
    end
    private_class_method :pick_plain_part

    def self.pick_html_part(mail)
      return nil if mail.parts.empty?

      mail.html_part&.decoded
    end
    private_class_method :pick_html_part

    def self.strip_html_to_text(html)
      doc = Nokogiri::HTML::DocumentFragment.parse(html)
      doc.css(
        "blockquote",
        ".gmail_quote",
        ".OutlookMessageHeader",
        ".gmail_signature",
        "[type='cite']",
        "div[class*='quote']",
        "div[id*='divRplyFwdMsg']"
      ).remove
      text = doc.text
      text.gsub(/ /, " ")
          .gsub(/[ \t]+/, " ")
          .gsub(/\n{3,}/, "\n\n")
          .strip
    end
    private_class_method :strip_html_to_text

    def self.normalize_for_compare(text)
      text.to_s.downcase.gsub(/\s+/, " ").strip
    end
    private_class_method :normalize_for_compare

    def self.assess_confidence(raw:, trimmed:, cleaned:)
      return :low    if cleaned.length < 2
      # A long reply where we never found a quote boundary is suspicious
      return :low    if trimmed == raw && raw.length > 5_000
      # Short replies (< 200 chars) are unlikely to contain hidden quote content
      return :high   if cleaned.length < 200
      return :high   if cleaned.length.between?(2, 1_000) && trimmed != raw

      :medium
    end
    private_class_method :assess_confidence
  end

  # ---------------------------------------------------------------------------
  # Skip Detector
  # Per L1.c: deterministic single-token-on-its-own-line predicate.
  # ---------------------------------------------------------------------------
  module SkipDetector
    SKIP_LINE = /\A[[:space:]]*skip[[:space:]]*[.,!?;…]?[[:space:]]*\z/i

    def self.skip?(cleaned_body)
      return false if cleaned_body.blank?

      cleaned_body.lines.any? { |line| line.match?(SKIP_LINE) }
    end
  end

  # ---------------------------------------------------------------------------
  # Thread Resolver
  # Per L2.c: In-Reply-To / References lookup against outbound_message_id.
  # ---------------------------------------------------------------------------
  module ThreadResolver
    def self.resolve_question(mail, tenant)
      candidate_ids = extract_message_ids(mail)
      return nil if candidate_ids.empty?

      normalized = candidate_ids.map { |id| id.to_s.delete("<>").strip }.reject(&:blank?)
      tenant.tenant_questions.where(outbound_message_id: normalized).first
    end

    def self.extract_message_ids(mail)
      in_reply_to = Array(mail.in_reply_to).flatten.compact
      references  = Array(mail.references).flatten.compact
      (in_reply_to + references).map(&:to_s).reject(&:blank?).uniq
    end
    private_class_method :extract_message_ids
  end

  # ---------------------------------------------------------------------------
  # Public entry point
  # ---------------------------------------------------------------------------

  def self.call(inbound_email:, tenant:)
    new(inbound_email: inbound_email, tenant: tenant).call
  end

  def initialize(inbound_email:, tenant:)
    @inbound_email = inbound_email
    @tenant        = tenant
    @mail          = inbound_email.mail
    @warnings      = []
  end

  def call
    # 1. Resolve which question this reply answers
    question = ThreadResolver.resolve_question(@mail, @tenant)
    @warnings << :question_unresolved if question.nil?

    # 2. Extract body
    body_result = BodyExtractor.extract(@mail)
    @warnings.concat(body_result[:warnings])
    cleaned_body = body_result[:body]

    # 3. Handle empty-body case
    if @warnings.include?(:empty_body) || cleaned_body.blank?
      return unparseable_reply(question: question)
    end

    # 4. CC ordering
    cc_addresses, cc_warnings = CcOrdering.normalize(@mail)
    @warnings.concat(cc_warnings)

    # 5. Attachment metadata
    @warnings << :has_attachments if @mail.attachments.present?

    # 6. Intent dispatch — skip wins over CCs per L1.c
    intent, primary, fallbacks = classify_intent(
      cleaned_body: cleaned_body,
      cc_addresses:  cc_addresses
    )

    # 7. Confidence
    confidence = combine_confidence(
      body_result[:confidence],
      intent_confidence(intent, cleaned_body)
    )

    # 8. raw_excerpt capped at 4 KB
    raw_excerpt = cleaned_body.byteslice(0, 4_096) || ""

    ParsedReply.new(
      intent:          intent,
      primary_email:   primary,
      fallback_emails: fallbacks,
      question:        question,
      raw_excerpt:     raw_excerpt,
      confidence:      confidence,
      warnings:        @warnings.uniq
    )
  rescue StandardError => e
    Rails.logger.tagged(tenant: @tenant&.id, flow: :onboarding, parser: :error).error(
      message:    "OnboardingReplyParser failed",
      error:      e.class.name,
      detail:     e.message,
      message_id: @mail&.message_id
    )
    ParsedReply.new(
      intent:          :unparseable,
      primary_email:   nil,
      fallback_emails: [],
      question:        nil,
      raw_excerpt:     "",
      confidence:      :low,
      warnings:        (@warnings + [ :parser_exception ]).uniq
    )
  end

  # ---------------------------------------------------------------------------
  private
  # ---------------------------------------------------------------------------

  def classify_intent(cleaned_body:, cc_addresses:)
    if SkipDetector.skip?(cleaned_body)
      @warnings << :skip_with_ccs_present if cc_addresses.any?
      return [ :skip, nil, [] ]
    end

    if cc_addresses.any?
      primary, *fallbacks = cc_addresses
      return [ :assign, primary, fallbacks ]
    end

    return [ :self_assign, @tenant.gm_email_normalized, [] ] if self_assign?(cleaned_body)
    return [ :clarification_response, nil, [] ] if clarification_response?(cleaned_body)

    [ :unparseable, nil, [] ]
  end

  def self_assign?(cleaned_body)
    return false if cleaned_body.blank?

    normalized = cleaned_body.downcase.strip

    return true if normalized.lines.any? do |l|
      l.strip.match?(/\A(me|that'?s me|i do|i am|i'?ll handle (it|this)|yes,?\s*me|it'?s me)[.!]?\z/)
    end

    return true if normalized.length <= 80 &&
                   normalized.match?(/\b(i'?ll (do it|handle (it|this))|that'?s me|it'?s me)\b/)

    false
  end

  def clarification_response?(cleaned_body)
    cleaned_body.strip.match?(/\A(internal|vendor:\s*\S)/i)
  end

  def intent_confidence(intent, body)
    case intent
    when :skip                   then :high
    when :assign                 then :high
    when :clarification_response then :high
    when :self_assign            then body.length <= 80 ? :high : :medium
    when :unparseable            then :high
    else :low
    end
  end

  def combine_confidence(c1, c2)
    order = { high: 2, medium: 1, low: 0 }
    [ c1, c2 ].min_by { |c| order.fetch(c, 0) }
  end

  def unparseable_reply(question:)
    ParsedReply.new(
      intent:          :unparseable,
      primary_email:   nil,
      fallback_emails: [],
      question:        question,
      raw_excerpt:     "",
      confidence:      :low,
      warnings:        @warnings.uniq
    )
  end
end
