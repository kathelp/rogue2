require "rails_helper"

RSpec.describe Accountability::DigestAssembler do
  let(:tenant) { create(:tenant, :active) }

  describe ".call" do
    it "returns an empty rows array and empty: true when the tenant has no responsibilities" do
      digest = described_class.call(tenant: tenant)
      expect(digest.rows).to eq([])
      expect(digest).to be_empty
    end

    it "returns one row per active responsibility" do
      q1 = create(:tenant_question, tenant: tenant, key: "marketing_strategy",
                  prompt: "Who controls your marketing strategy?")
      q2 = create(:tenant_question, tenant: tenant, key: "dealer_website",
                  prompt: "Who manages your dealer website?")
      c1 = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      c2 = create(:contact, tenant: tenant, email: "taylor@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q1, primary_contact: c1)
      create(:responsibility, tenant: tenant, tenant_question: q2, primary_contact: c2)

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.length).to eq(2)
      expect(digest).not_to be_empty
    end

    it "marks pending_setup when the source is not yet configured" do
      q = create(:tenant_question, tenant: tenant, key: "marketing_strategy",
                 prompt: "Who controls your marketing strategy?")
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q, primary_contact: c)
      create(:source, tenant: tenant, domain: "marketing", responsibility_key: "marketing_strategy")

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.first.status).to eq(:pending_setup)
    end

    it "marks pending_first_submission when configured but no submissions yet" do
      q = create(:tenant_question, tenant: tenant, key: "marketing_strategy",
                 prompt: "Who controls your marketing strategy?")
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q, primary_contact: c)
      source = create(:source, :configured, tenant: tenant, domain: "marketing",
                      responsibility_key: "marketing_strategy", configured_by_contact: c)
      create(:request, tenant: tenant, source: source, metric_key: "strategy_summary",
             cadence: "monthly")

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.first.status).to eq(:pending_first_submission)
    end

    it "ignores superseded responsibilities" do
      q = create(:tenant_question, tenant: tenant, key: "marketing_strategy",
                 prompt: "Who controls your marketing strategy?")
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, :superseded, tenant: tenant, tenant_question: q, primary_contact: c)

      digest = described_class.call(tenant: tenant)
      expect(digest.rows).to eq([])
    end
  end
end
