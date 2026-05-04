require "rails_helper"

RSpec.describe SubmissionMailer, type: :mailer do
  let(:tenant) do
    create(:tenant, :confirmed,
           dealership_name: "Smith Toyota",
           gm_email: "jane@smithtoyota.com",
           onboarding_token: "subtoken9999abc")
  end
  let(:contact) { create(:contact, tenant: tenant, email: "alex@smithtoyota.com") }
  let(:source) do
    create(:source, :configured,
           tenant: tenant,
           responsibility_key: "marketing_strategy",
           configured_by_contact: contact)
  end
  let(:request_record) do
    create(:request, tenant: tenant, source: source, metric_key: "strategy_summary", cadence: "monthly")
  end
  let(:prompt) do
    create(:submission_prompt,
           tenant: tenant,
           request: request_record,
           scheduled_for: Time.zone.parse("2026-05-01 10:00:00"))
  end

  describe "#prompt_email" do
    let(:mail) { described_class.with(prompt: prompt).prompt_email }

    it "sends to the configured_by_contact" do
      expect(mail.to).to eq([ "alex@smithtoyota.com" ])
    end

    it "subject names the dealership and the metric label and the period" do
      expect(mail.subject).to include("Smith Toyota")
      expect(mail.subject).to include("strategy summary")
    end

    it "is from the per-tenant onboarding address" do
      expect(mail.from.first).to include("onboarding+subtoken9999abc@inbound.rogue.example")
    end

    it "has both html and text alternatives" do
      expect(mail.html_part).not_to be_nil
      expect(mail.text_part).not_to be_nil
    end

    it "html body contains the Submit your data CTA" do
      expect(mail.html_part.body.decoded).to include("Submit your data")
    end

    it "html body contains a link to /submissions/<signed_id>" do
      expect(mail.html_part.body.decoded).to match(%r{/submissions/[A-Za-z0-9._\-]+})
    end

    it "text body contains the submission URL" do
      expect(mail.text_part.body.decoded).to match(%r{/submissions/[A-Za-z0-9._\-]+})
    end
  end

  describe "#adapter_pending_email" do
    let(:csv_source) do
      create(:source,
             tenant: tenant,
             responsibility_key: "dealer_website",
             submission_method: "csv",
             configured_at: Time.current,
             configured_by_contact: contact)
    end
    let(:csv_request) do
      create(:request, tenant: tenant, source: csv_source, metric_key: "website_traffic", cadence: "monthly")
    end
    let(:csv_prompt) do
      create(:submission_prompt,
             tenant: tenant,
             request: csv_request,
             scheduled_for: Time.zone.parse("2026-05-01 10:00:00"))
    end
    let(:mail) { described_class.with(prompt: csv_prompt).adapter_pending_email }

    it "sends to the configured contact" do
      expect(mail.to).to eq([ "alex@smithtoyota.com" ])
    end

    it "subject mentions the parked state (CSV adapter)" do
      expect(mail.subject).to match(/adapter|CSV|csv/i)
    end

    it "body explains no action is needed yet" do
      expect(mail.html_part.body.decoded).to match(/we'll be in touch|no action/i)
    end
  end
end
