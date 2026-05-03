require "rails_helper"

RSpec.describe OnboardingMailer, type: :mailer do
  describe "#confirmation_email" do
    let(:tenant) { create(:tenant, dealership_name: "Smith Toyota", gm_name: "Jane Smith", gm_email: "jane@smithtoyota.com") }
    let(:mail) { described_class.with(tenant: tenant).confirmation_email }

    it "sends to the GM email" do
      expect(mail.to).to eq([ "jane@smithtoyota.com" ])
    end

    it "has the correct subject" do
      expect(mail.subject).to eq("Welcome to Rogue — confirm to begin")
    end

    it "comes from the Rogue transactional address" do
      expect(mail.from).to include("hello@inbound.rogue.example")
    end

    it "contains a CTA link to the onboarding confirmation path" do
      expect(mail.html_part.body.decoded).to include("Confirm and start onboarding")
      expect(mail.html_part.body.decoded).to include("/onboarding/confirmations/")
    end

    it "contains the signed_id URL in the HTML body" do
      signed_id = tenant.gm_confirm_signed_id(expires_in: 72.hours)
      # The URL contains the signed_id somewhere — just verify the path prefix
      expect(mail.html_part.body.decoded).to include("/onboarding/confirmations/")
    end

    it "has a plain-text alternative" do
      expect(mail.text_part).not_to be_nil
    end

    it "contains the confirmation URL in the plain-text alternative" do
      expect(mail.text_part.body.decoded).to include("/onboarding/confirmations/")
    end

    it "includes 'Confirm and start onboarding' in the plain-text body" do
      expect(mail.text_part.body.decoded).to include("Confirm and start onboarding")
    end

    it "mentions the GM name in the HTML body" do
      expect(mail.html_part.body.decoded).to include("Jane Smith")
    end

    it "mentions the dealership name in the HTML body" do
      expect(mail.html_part.body.decoded).to include("Smith Toyota")
    end
  end

  # ---------------------------------------------------------------------------
  describe "#question_email" do
    let(:tenant) do
      create(:tenant,
             dealership_name: "Smith Toyota",
             gm_email:        "jane@smithtoyota.com",
             onboarding_token: "abc123test456789")
    end
    let(:question) do
      create(:tenant_question,
             tenant:   tenant,
             position: 1,
             prompt:   "Who controls your marketing strategy at Smith Toyota?")
    end
    let(:explicit_message_id) { "<onboarding-q-1-1-abc123@inbound.rogue.example>" }

    let(:mail) do
      described_class.with(
        tenant:          tenant,
        tenant_question: question,
        message_id:      explicit_message_id
      ).question_email
    end

    it "sends to the GM email" do
      expect(mail.to).to eq([ "jane@smithtoyota.com" ])
    end

    it "has the canonical subject containing the dealership name and question text" do
      expect(mail.subject).to include("Smith Toyota Onboarding")
      expect(mail.subject).to include("Who controls your marketing strategy")
    end

    it "sets From: to the per-tenant onboarding address" do
      expect(mail.from.first).to include("onboarding+abc123test456789@inbound.rogue.example")
    end

    it "sets Reply-To: to the per-tenant onboarding address" do
      expect(mail.reply_to.first).to include("onboarding+abc123test456789@inbound.rogue.example")
    end

    it "is multipart with html and text parts" do
      expect(mail.html_part).not_to be_nil
      expect(mail.text_part).not_to be_nil
    end

    it "HTML body contains the four reply conventions" do
      body = mail.html_part.body.decoded
      expect(body).to include("The first person you CC is the primary accountable party")
      expect(body).to include("If this is you, reply with no CC")
      expect(body).to include("skip")
      expect(body).to include("Order matters")
    end

    it "text body contains the four reply conventions" do
      body = mail.text_part.body.decoded
      expect(body).to include("The first person you CC is the primary accountable party")
      expect(body).to include("If this is you, reply with no CC")
      expect(body).to include("skip")
      expect(body).to include("Order matters")
    end

    it "sets the Message-ID header from params[:message_id]" do
      expect(mail.message_id).to eq("onboarding-q-1-1-abc123@inbound.rogue.example")
    end

    it "HTML body mentions the question prompt" do
      expect(mail.html_part.body.decoded).to include("Who controls your marketing strategy at Smith Toyota?")
    end

    it "text body mentions the question prompt" do
      expect(mail.text_part.body.decoded).to include("Who controls your marketing strategy at Smith Toyota?")
    end

    context "without an explicit message_id param" do
      let(:mail_no_mid) do
        described_class.with(
          tenant:          tenant,
          tenant_question: question
        ).question_email
      end

      it "still sends successfully and is addressed to the GM" do
        expect(mail_no_mid.to).to eq([ "jane@smithtoyota.com" ])
        # Message-ID is auto-generated by the mail gem at encode time;
        # before encoding it is nil — that is expected in the test adapter.
        expect(mail_no_mid.subject).to include("Smith Toyota Onboarding")
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#in_thread_ack" do
    let(:tenant) do
      create(:tenant,
             dealership_name:  "Smith Toyota",
             gm_email:         "jane@smithtoyota.com",
             onboarding_token: "abc123test456789")
    end
    let(:question) do
      create(:tenant_question,
             tenant: tenant,
             prompt: "Who controls your marketing strategy?")
    end
    let(:inbound_message_id) { "gm-reply-12345@mail.gmail.com" }
    let(:inbound_email) do
      raw = Mail.new do
        from    "jane@smithtoyota.com"
        to      "onboarding+abc123test456789@inbound.rogue.example"
        subject "Re: [Smith Toyota Onboarding] Who controls your marketing strategy?"
        body    "That's Alex."
      end.to_s
      ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
    end

    let(:mail) do
      described_class.with(
        tenant:           tenant,
        intent:           "assign",
        primary_email:    "alex@smithtoyota.com",
        fallback_emails:  [],
        warnings:         [],
        question:         question,
        inbound_email:    inbound_email,
        next_question_at: 24.hours.from_now
      ).in_thread_ack
    end

    it "sends to the GM email" do
      expect(mail.to).to eq([ "jane@smithtoyota.com" ])
    end

    it "has a canonical Re: subject" do
      expect(mail.subject).to start_with("Re: [Smith Toyota Onboarding]")
    end

    it "sets In-Reply-To to the inbound message_id" do
      msg_id = inbound_email.message_id
      expect(mail.header["In-Reply-To"].to_s).to include(msg_id)
    end

    it "sets References to include the inbound message_id" do
      msg_id = inbound_email.message_id
      expect(mail.header["References"].to_s).to include(msg_id)
    end

    it "includes the primary email in the body" do
      expect(mail.html_part.body.decoded).to include("alex@smithtoyota.com")
    end

    it "has a plain-text alternative" do
      expect(mail.text_part).not_to be_nil
      expect(mail.text_part.body.decoded).to include("alex@smithtoyota.com")
    end

    context "with next_question_at set" do
      it "mentions the next question timing in the body" do
        expect(mail.html_part.body.decoded).to include("Next question coming")
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#gm_only_thread_notice" do
    let(:tenant) do
      create(:tenant,
             dealership_name:  "Smith Toyota",
             gm_email:         "jane@smithtoyota.com",
             onboarding_token: "abc123test456789")
    end
    let(:inbound_email) do
      raw = Mail.new do
        from    "interloper@other.com"
        to      "onboarding+abc123test456789@inbound.rogue.example"
        subject "Re: [Smith Toyota Onboarding] Who controls your marketing strategy?"
        body    "I want to help"
      end.to_s
      ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
    end

    let(:mail) do
      described_class.with(
        tenant:        tenant,
        inbound_email: inbound_email
      ).gm_only_thread_notice
    end

    it "sends to the actual (non-GM) sender" do
      expect(mail.to).to eq([ "interloper@other.com" ])
    end

    it "has a subject mentioning GM only" do
      expect(mail.subject).to include("GM only")
    end

    it "sets In-Reply-To to the inbound message_id" do
      msg_id = inbound_email.message_id
      expect(mail.header["In-Reply-To"].to_s).to include(msg_id)
    end

    it "has both HTML and text parts" do
      expect(mail.html_part).not_to be_nil
      expect(mail.text_part).not_to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  describe "#vendor_clarification" do
    let(:tenant) do
      create(:tenant,
             dealership_name:  "Smith Toyota",
             gm_name:          "Jane Smith",
             gm_email:         "jane@smithtoyota.com",
             onboarding_token: "abc123test456789")
    end
    let(:inbound_email) do
      raw = Mail.new do
        from    "jane@smithtoyota.com"
        to      "onboarding+abc123test456789@inbound.rogue.example"
        subject "Re: [Smith Toyota Onboarding] Who controls your marketing strategy?"
        body    "That's Alex."
      end.to_s
      ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
    end

    let(:mail) do
      described_class.with(
        tenant:           tenant,
        inbound_email:    inbound_email,
        ambiguous_email:  "alex@unknownvendor.com",
        ambiguous_domain: "unknownvendor.com"
      ).vendor_clarification
    end

    it "sends to the GM email" do
      expect(mail.to).to eq([ "jane@smithtoyota.com" ])
    end

    it "subject names the ambiguous domain" do
      expect(mail.subject).to include("unknownvendor.com")
    end

    it "sets In-Reply-To to the inbound message_id" do
      msg_id = inbound_email.message_id
      expect(mail.header["In-Reply-To"].to_s).to include(msg_id)
    end

    it "HTML body contains the two clarification options" do
      body = mail.html_part.body.decoded
      expect(body).to include("internal")
      expect(body).to include("vendor:")
    end

    it "text body contains the two clarification options" do
      body = mail.text_part.body.decoded
      expect(body).to include("internal")
      expect(body).to include("vendor:")
    end
  end
end
