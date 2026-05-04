require "rails_helper"

RSpec.describe EscalationMailer, type: :mailer do
  let(:tenant) do
    create(:tenant, :confirmed,
           dealership_name: "Smith Toyota", gm_email: "jane@smithtoyota.com",
           gm_name: "Jane Smith", onboarding_token: "esctok9999")
  end
  let(:contact) { create(:contact, tenant: tenant, email: "alex@smithtoyota.com") }
  let(:source) do
    create(:source, :configured, tenant: tenant,
           responsibility_key: "marketing_strategy", configured_by_contact: contact)
  end
  let(:request_record) do
    create(:request, tenant: tenant, source: source,
           metric_key: "strategy_summary", cadence: "monthly")
  end
  let(:prompt) do
    create(:submission_prompt, tenant: tenant, request: request_record,
           status: "sent", scheduled_for: Time.zone.parse("2026-05-01 09:00:00"))
  end

  describe "#escalation_email" do
    context "severity: :due_soon" do
      let(:mail) do
        described_class.with(
          prompt:    prompt,
          severity:  :due_soon,
          recipient: "alex@smithtoyota.com",
          payload:   { period_end: "2026-05-31" }
        ).escalation_email
      end

      it "sends to the recipient" do
        expect(mail.to).to eq([ "alex@smithtoyota.com" ])
      end

      it "subject mentions due-soon framing" do
        expect(mail.subject).to match(/due/i)
      end

      it "html body includes the magic-link" do
        expect(mail.html_part.body.decoded).to match(%r{/submissions/[A-Za-z0-9._\-]+})
      end

      it "is from the per-tenant onboarding address" do
        expect(mail.from.first).to include("onboarding+esctok9999@inbound.rogue.example")
      end
    end

    context "severity: :overdue" do
      let(:mail) do
        described_class.with(
          prompt: prompt, severity: :overdue, recipient: "alex@smithtoyota.com",
          payload: {}
        ).escalation_email
      end

      it "subject says overdue" do
        expect(mail.subject).to match(/overdue/i)
      end
    end

    context "severity: :fallback_fanout" do
      let(:mail) do
        described_class.with(
          prompt: prompt, severity: :fallback_fanout, recipient: "taylor@smithtoyota.com",
          payload: { fallback_index: 0, fallback_email: "taylor@smithtoyota.com" }
        ).escalation_email
      end

      it "sends to the fallback recipient" do
        expect(mail.to).to eq([ "taylor@smithtoyota.com" ])
      end

      it "subject signals overdue framing (same as overdue)" do
        expect(mail.subject).to match(/overdue/i)
      end
    end

    context "severity: :gm_nudge" do
      let(:mail) do
        described_class.with(
          prompt:    prompt,
          severity:  :gm_nudge,
          recipient: "jane@smithtoyota.com",
          payload:   { period_end: "2026-05-31", fallback_chain: [ "taylor@smithtoyota.com" ] }
        ).escalation_email
      end

      it "sends to the GM" do
        expect(mail.to).to eq([ "jane@smithtoyota.com" ])
      end

      it "subject is the still-no-data nudge" do
        expect(mail.subject).to match(/still no/i)
      end

      it "body lists the fallback chain that was pinged" do
        expect(mail.html_part.body.decoded).to include("taylor@smithtoyota.com")
      end
    end
  end
end
