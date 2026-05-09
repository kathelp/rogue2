require "rails_helper"

RSpec.describe Setup::Completion do
  let(:tenant) { create(:tenant, :confirmed) }
  let(:question) do
    create(
      :tenant_question,
      tenant: tenant,
      key: "marketing_strategy",
      prompt: "Who controls your marketing strategy?",
      default_cadence: "monthly"
    )
  end

  let(:contact) { create(:contact, tenant: tenant) }
  let!(:responsibility) do
    create(
      :responsibility,
      tenant: tenant,
      tenant_question: question,
      primary_contact: contact
    )
  end

  let(:source) do
    create(
      :source,
      tenant: tenant,
      domain: "marketing",
      responsibility_key: "marketing_strategy"
    )
  end

  describe ".call" do
    it "updates Source.submission_method, configured_at, configured_by_contact" do
      freeze_time do
        described_class.call(source: source, contact: contact, submission_method: "form")
        source.reload
        expect(source.submission_method).to(eq("form"))
        expect(source.configured_at).to(be_within(1.second).of(Time.current))
        expect(source.configured_by_contact_id).to(eq(contact.id))
      end
    end

    it "creates Request rows for each catalog metric of the question" do
      expect {
        described_class.call(source: source, contact: contact, submission_method: "form")
      }
        .to(change { Request.where(source: source).count }.from(0).to(1))
      # marketing_strategy in catalog v1 has one metric: strategy_summary
      expect(Request.where(source: source).pluck(:metric_key)).to(include("strategy_summary"))
    end

    it "schedules at least one SubmissionPrompt for each created Request" do
      described_class.call(source: source, contact: contact, submission_method: "form")
      expect(SubmissionPrompt.where(tenant: tenant).count).to(be >= 1)
    end

    it "is idempotent — calling twice does not duplicate Requests" do
      described_class.call(source: source, contact: contact, submission_method: "form")
      expect {
        described_class.call(source: source, contact: contact, submission_method: "form")
      }
        .not_to(change { Request.where(source: source).count })
    end

    it "rejects an unknown submission_method with an error result" do
      result = described_class.call(source: source, contact: contact, submission_method: "carrier_pigeon")
      expect(result.success?).to(be(false))
      expect(source.reload.submission_method).to(be_nil)
    end
  end
end
