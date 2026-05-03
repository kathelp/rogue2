require "rails_helper"

RSpec.describe OnboardingFlow::RequestProvisioning do
  let(:tenant) { create(:tenant, :confirmed) }
  let(:question) do
    create(:tenant_question,
           tenant: tenant,
           key:    "marketing_strategy",
           prompt: "Who controls your marketing strategy?",
           default_cadence: "monthly")
  end
  let(:source) do
    create(:source,
           tenant:             tenant,
           domain:             "marketing",
           responsibility_key: "marketing_strategy")
  end

  describe ".call" do
    it "creates one Request row per catalog metric of the question" do
      expect {
        described_class.call(source: source, tenant_question: question)
      }.to change { Request.where(source: source).count }.from(0).to(1)
      # marketing_strategy in catalog v1 has one metric (strategy_summary, monthly)
      r = Request.where(source: source).first
      expect(r.metric_key).to eq("strategy_summary")
      expect(r.cadence).to eq("monthly")
    end

    it "creates multiple Requests when the catalog metric list has multiple entries" do
      multi_q = create(:tenant_question,
                       tenant: tenant,
                       key: "dealer_website",
                       prompt: "Who manages your dealer website?",
                       default_cadence: "monthly")
      multi_source = create(:source,
                            tenant: tenant,
                            domain: "marketing",
                            responsibility_key: "dealer_website")
      expect {
        described_class.call(source: multi_source, tenant_question: multi_q)
      }.to change { Request.where(source: multi_source).count }.from(0).to(2)
    end

    it "is idempotent — re-calling does not duplicate Requests" do
      described_class.call(source: source, tenant_question: question)
      expect {
        described_class.call(source: source, tenant_question: question)
      }.not_to change { Request.where(source: source).count }
    end

    it "no-ops gracefully when the catalog has no entry for the question key" do
      question.update!(key: "no_such_question_key")
      expect {
        described_class.call(source: source, tenant_question: question)
      }.not_to change(Request, :count)
    end
  end
end
