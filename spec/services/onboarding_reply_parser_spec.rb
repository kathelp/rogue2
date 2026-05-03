require "rails_helper"

RSpec.describe OnboardingReplyParser, type: :service do
  let(:tenant) do
    create(:tenant,
           dealership_name: "Smith Toyota",
           gm_email:        "jane@smithtoyota.com")
  end
  let(:question) do
    create(:tenant_question,
           tenant:                tenant,
           key:                   "marketing_strategy",
           prompt:                "Who controls your marketing strategy?",
           outbound_message_id:   "abc123@inbound.rogue.example")
  end

  # Helper: build a minimal Mail::Message that looks like a reply to the question
  def build_mail(from:, cc: nil, body:, in_reply_to: nil, content_type: "text/plain")
    msg = Mail.new
    msg.from    = from
    msg.to      = "onboarding+#{tenant.onboarding_token}@inbound.rogue.example"
    msg.cc      = cc if cc.present?
    msg.subject = "Re: [Smith Toyota Onboarding] Who controls your marketing strategy?"
    msg.in_reply_to = "<#{in_reply_to}>" if in_reply_to
    msg.body    = body
    msg.content_type = content_type
    msg
  end

  def build_inbound_email(mail_message)
    raw  = mail_message.to_s
    ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
  end

  before { question } # ensure question exists so thread resolution can work

  # ---------------------------------------------------------------------------
  describe ":assign intent" do
    it "detects assign with one CC — high confidence, ordered lists" do
      mail_msg = build_mail(
        from:       "jane@smithtoyota.com",
        cc:         "alex@smithtoyota.com",
        body:       "That's Alex, our CMO.",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:assign)
      expect(result.primary_email).to eq("alex@smithtoyota.com")
      expect(result.fallback_emails).to eq([])
      expect(result.confidence).to eq(:high)
    end

    it "detects assign with three CCs — preserves wire order" do
      mail_msg = build_mail(
        from:       "jane@smithtoyota.com",
        cc:         "alex@smithtoyota.com, taylor@smithtoyota.com, casey@smithtoyota.com",
        body:       "These three handle it.",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:assign)
      expect(result.primary_email).to eq("alex@smithtoyota.com")
      expect(result.fallback_emails).to eq([ "taylor@smithtoyota.com", "casey@smithtoyota.com" ])
    end

    it "resolves the question via In-Reply-To" do
      mail_msg = build_mail(
        from:       "jane@smithtoyota.com",
        cc:         "alex@smithtoyota.com",
        body:       "Alex handles this.",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.question).to eq(question)
    end

    it "warns :question_unresolved when In-Reply-To doesn't match any question" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        cc:   "alex@smithtoyota.com",
        body: "That's Alex.",
        in_reply_to: "no-such-message-id@example.com"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.warnings).to include(:question_unresolved)
    end
  end

  # ---------------------------------------------------------------------------
  describe ":self_assign intent" do
    it "detects self-assign when body is 'that's me' with no CCs" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "that's me",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:self_assign)
      expect(result.primary_email).to eq("jane@smithtoyota.com")
      expect(result.confidence).to eq(:high)
    end

    it "detects self-assign when body is 'I'll handle it'" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "I'll handle it",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:self_assign)
      expect(result.primary_email).to eq("jane@smithtoyota.com")
    end

    it "detects self-assign when body is 'me' on its own line" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "me",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:self_assign)
    end
  end

  # ---------------------------------------------------------------------------
  describe ":skip intent" do
    it "detects skip on its own line" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "skip",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:skip)
      expect(result.confidence).to eq(:high)
    end

    it "detects skip with trailing punctuation" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "Skip!",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:skip)
    end

    it "detects skip when it appears on its own line with prose around it" do
      body = "Hey,\nskip\nlet's revisit this next quarter"
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: body,
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:skip)
    end

    it "does NOT treat 'skipping this for now' as skip (word inside phrase)" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "skipping this for now",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).not_to eq(:skip)
    end

    it "does NOT false-positive on 'skip' inside what was originally a quoted block" do
      # EmailReplyTrimmer should strip quoted content; "skip" inside should not match
      quoted_body = "Hey, that sounds good.\n\n> On May 3, Rogue wrote:\n> skip this question"
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: quoted_body,
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).not_to eq(:skip)
    end

    it "emits :skip_with_ccs_present warning when CCs are present alongside skip" do
      mail_msg = build_mail(
        from:       "jane@smithtoyota.com",
        cc:         "alex@smithtoyota.com",
        body:       "skip",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:skip)
      expect(result.warnings).to include(:skip_with_ccs_present)
    end
  end

  # ---------------------------------------------------------------------------
  describe ":unparseable intent" do
    it "marks empty body as unparseable" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:unparseable)
    end

    it "marks 'sounds good' with no CCs as unparseable" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "sounds good",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:unparseable)
    end
  end

  # ---------------------------------------------------------------------------
  describe ":clarification_response intent" do
    it "classifies 'internal' as clarification_response" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "internal",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:clarification_response)
    end

    it "classifies 'vendor: Acme Corp' as clarification_response" do
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        body: "vendor: Acme Corp",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:clarification_response)
    end
  end

  # ---------------------------------------------------------------------------
  describe "attachment handling" do
    it "emits :has_attachments warning but does not affect intent when CCs present" do
      mail_msg = build_mail(
        from:       "jane@smithtoyota.com",
        cc:         "alex@smithtoyota.com",
        body:       "Here's the info.",
        in_reply_to: "abc123@inbound.rogue.example"
      )
      # Attach a fake file
      mail_msg.add_file filename: "org_chart.pdf", content: "PDF content"

      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.intent).to eq(:assign)
      expect(result.warnings).to include(:has_attachments)
    end
  end

  # ---------------------------------------------------------------------------
  describe "raw_excerpt" do
    it "caps raw_excerpt at 4 KB" do
      long_body = "a" * 10_000
      mail_msg = build_mail(
        from: "jane@smithtoyota.com",
        cc:   "alex@smithtoyota.com",
        body: long_body,
        in_reply_to: "abc123@inbound.rogue.example"
      )
      ie = build_inbound_email(mail_msg)
      result = described_class.call(inbound_email: ie, tenant: tenant)

      expect(result.raw_excerpt.bytesize).to be <= 4_096
    end
  end
end
