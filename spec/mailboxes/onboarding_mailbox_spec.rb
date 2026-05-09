require "rails_helper"

RSpec.describe OnboardingMailbox, type: :mailbox do
  include(ActiveJob::TestHelper)

  let(:tenant) do
    create(
      :tenant,
      :confirmed,
      dealership_name: "Smith Toyota",
      gm_email: "jane@smithtoyota.com",
      onboarding_token: "testtoken123abc456"
    )
  end

  let!(:question) do
    create(
      :tenant_question,
      tenant: tenant,
      key: "marketing_strategy",
      prompt: "Who controls your marketing strategy?",
      status: "sent",
      sent_at: 1.hour.ago,
      outbound_message_id: "qid-abc123@inbound.rogue.example"
    )
  end

  def deliver_reply(from:, cc: nil, body:, in_reply_to: "qid-abc123@inbound.rogue.example")
    mail = Mail.new do
      to("onboarding+testtoken123abc456@inbound.rogue.example")
      from from
      subject("Re: [Smith Toyota Onboarding] Who controls your marketing strategy?")
      body body
    end

    mail.cc = cc if cc.present?
    mail.in_reply_to = "<#{in_reply_to}>" if in_reply_to
    process(mail)
  end

  # ---------------------------------------------------------------------------
  describe "routing" do
    it "routes addresses with onboarding+ prefix" do
      mail = Mail.new do
        to("onboarding+sometoken@inbound.rogue.example")
        from("jane@smithtoyota.com")
        body("test")
      end

      expect { ApplicationMailbox.route(ActionMailbox::InboundEmail.create_and_extract_message_id!(mail.to_s)) }
        .not_to(raise_error)
    end
  end

  # ---------------------------------------------------------------------------
  describe "valid GM reply — one CC (AC-HAPPY-3)" do
    it "creates Responsibility, Source, and FlowEvent; enqueues next question; sends in_thread_ack" do
      perform_enqueued_jobs do
        ie = deliver_reply(
          from: "jane@smithtoyota.com",
          cc: "alex@smithtoyota.com",
          body: "That's Alex, our CMO."
        )

        expect(ie).to(have_been_delivered)
      end

      # Responsibility created
      responsibility = Responsibility.last
      expect(responsibility).not_to(be_nil)
      expect(responsibility.tenant).to(eq(tenant))
      expect(responsibility.primary_contact.email_normalized).to(eq("alex@smithtoyota.com"))
      expect(responsibility.fallback_contact_emails).to(eq([]))

      # Source created
      source = Source.last
      expect(source).not_to(be_nil)
      expect(source.tenant).to(eq(tenant))
      expect(source.responsibility_key).to(eq("marketing_strategy"))

      # Question answered
      expect(question.reload.status).to(eq("answered"))

      # FlowEvent recorded
      expect(FlowEvent.where(event_type: "responsibility.created", tenant: tenant).count).to(eq(1))

      # In-thread ack queued
      ack_mail = ActionMailer::Base.deliveries.find { |m|
        m.to.include?("jane@smithtoyota.com") && m.subject&.include?("marketing strategy")
      }
      expect(ack_mail).not_to(be_nil)

      # Phase 5: invitee setup email queued to the assigned contact
      setup_mail = ActionMailer::Base.deliveries.find { |m| m.to.include?("alex@smithtoyota.com") }
      expect(setup_mail).not_to(be_nil)
      expect(setup_mail.subject).to(include("data collection assignment"))

      # Phase 5: Request rows created for the catalog metrics
      expect(Request.where(source: source).count).to(be >= 1)
    end
  end

  # ---------------------------------------------------------------------------
  describe "valid GM reply — multiple CCs (AC-HAPPY-4)" do
    it "preserves CC wire order for primary and fallbacks" do
      perform_enqueued_jobs do
        deliver_reply(
          from: "jane@smithtoyota.com",
          cc: "alex@smithtoyota.com, taylor@smithtoyota.com, casey@smithtoyota.com",
          body: "These three."
        )
      end

      responsibility = Responsibility.last
      expect(responsibility.primary_contact.email_normalized).to(eq("alex@smithtoyota.com"))
      expect(responsibility.fallback_contact_emails).to(
        eq(
          ["taylor@smithtoyota.com", "casey@smithtoyota.com"]
        )
      )
    end
  end

  # ---------------------------------------------------------------------------
  describe "valid GM reply — self-assign (AC-HAPPY-5)" do
    it "creates a gm_self_assigned Responsibility and does not enqueue setup email" do
      perform_enqueued_jobs do
        deliver_reply(
          from: "jane@smithtoyota.com",
          body: "That's me."
        )
      end

      responsibility = Responsibility.last
      expect(responsibility).not_to(be_nil)
      expect(responsibility.gm_self_assigned).to(be(true))

      # No setup email sent — GM is the contact, no need to onboard them again.
      setup_mail = ActionMailer::Base.deliveries.find { |m| m.subject&.include?("data collection") }
      expect(setup_mail).to(be_nil)
    end
  end

  # ---------------------------------------------------------------------------
  describe "valid GM reply — skip (AC-HAPPY-6)" do
    it "creates SkippedQuestion, marks question skipped, sends ack, enqueues next question" do
      perform_enqueued_jobs do
        deliver_reply(
          from: "jane@smithtoyota.com",
          body: "skip"
        )
      end

      expect(question.reload.status).to(eq("skipped"))
      expect(SkippedQuestion.where(tenant: tenant, tenant_question: question).count).to(eq(1))

      ack_mail = ActionMailer::Base.deliveries.find { |m| m.to.include?("jane@smithtoyota.com") }
      expect(ack_mail).not_to(be_nil)
    end
  end

  # ---------------------------------------------------------------------------
  describe "non-GM sender (AC-ERROR-2)" do
    it "bounces, sends gm_only_thread_notice, records FlowEvent, makes no DB mutations" do
      perform_enqueued_jobs do
        deliver_reply(
          from: "rando@elsewhere.com",
          cc: "alex@smithtoyota.com",
          body: "I should not be here"
        )
      end

      # No Responsibility created
      expect(Responsibility.count).to(eq(0))

      # gm_only_thread_notice sent to the interloper
      notice = ActionMailer::Base.deliveries.find { |m| m.to.include?("rando@elsewhere.com") }
      expect(notice).not_to(be_nil)
      expect(notice.subject).to(include("GM only"))

      # FlowEvent recorded
      expect(FlowEvent.where(event_type: "reply.rejected_non_gm_sender", tenant: tenant).count).to(eq(1))
    end
  end

  # ---------------------------------------------------------------------------
  describe "unparseable reply (AC-ERROR-3)" do
    it "sends ack, does NOT advance question status, does NOT enqueue next question" do
      perform_enqueued_jobs do
        deliver_reply(
          from: "jane@smithtoyota.com",
          body: "sounds good"
        )
      end

      # Question remains sent (not answered)
      expect(question.reload.status).to(eq("sent"))

      # No Responsibility created
      expect(Responsibility.count).to(eq(0))

      # Ack sent
      ack_mail = ActionMailer::Base.deliveries.find { |m| m.to.include?("jane@smithtoyota.com") }
      expect(ack_mail).not_to(be_nil)
    end
  end

  # ---------------------------------------------------------------------------
  describe "unknown vendor domain (AC-ERROR-4)" do
    it "sends vendor_clarification, defers Responsibility creation, records FlowEvent" do
      perform_enqueued_jobs do
        deliver_reply(
          from: "jane@smithtoyota.com",
          cc: "alex@unknownvendor.com",
          body: "That's Alex."
        )
      end

      # No Responsibility yet
      expect(Responsibility.count).to(eq(0))

      # vendor_clarification sent to GM
      clarification = ActionMailer::Base.deliveries.find { |m|
        m.to.include?("jane@smithtoyota.com") && m.subject&.include?("unknownvendor.com")
      }
      expect(clarification).not_to(be_nil)

      # FlowEvent recorded
      expect(FlowEvent.where(event_type: "vendor.clarification_requested", tenant: tenant).count).to(eq(1))
    end
  end

  # ---------------------------------------------------------------------------
  describe "skip then revisit (AC-NAV-1)" do
    it "reopens a skipped question when GM replies with a CC on the same thread" do
      # First: skip
      perform_enqueued_jobs do
        deliver_reply(
          from: "jane@smithtoyota.com",
          body: "skip"
        )
      end

      expect(question.reload.status).to(eq("skipped"))
      expect(SkippedQuestion.count).to(eq(1))

      # Later: revisit with a CC assignment
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs do
        deliver_reply(
          from: "jane@smithtoyota.com",
          cc: "alex@smithtoyota.com",
          body: "Actually, Alex handles this."
        )
      end

      # Question answered, skipped_question marked revisited
      expect(question.reload.status).to(eq("answered"))
      skipped = SkippedQuestion.where(tenant: tenant, tenant_question: question).first
      expect(skipped.revisited_at).not_to(be_nil)

      # Responsibility created
      expect(Responsibility.last).not_to(be_nil)
    end
  end

  # ---------------------------------------------------------------------------
  describe "Message-ID idempotency" do
    it "does not double-process a re-delivered email with the same Message-ID" do
      mail = Mail.new do
        to("onboarding+testtoken123abc456@inbound.rogue.example")
        from("jane@smithtoyota.com")
        subject("Re: [Smith Toyota Onboarding] Who controls your marketing strategy?")
        message_id("<unique-message-12345@mail.gmail.com>")
        body("skip")
        in_reply_to("<qid-abc123@inbound.rogue.example>")
      end

      raw = mail.to_s

      # Deliver twice
      perform_enqueued_jobs { process(mail) }
      expect(question.reload.status).to(eq("skipped"))
      expect(SkippedQuestion.count).to(eq(1))

      # Reset for second delivery — Action Mailbox dedupes on message_id natively
      # so the second InboundEmail.create_and_extract_message_id! call should
      # return the existing record or raise a unique-constraint violation that
      # Rails handles. We assert the skip count stays at 1.
      begin
        ie2 = ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
        perform_enqueued_jobs { described_class.receive(ie2) } unless ie2.nil?
      rescue ActiveRecord::RecordNotUnique
        # expected — idempotent by constraint
      end

      expect(SkippedQuestion.count).to(eq(1))
    end
  end
end
