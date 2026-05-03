require "rails_helper"

RSpec.describe OnboardingFlow::SubmissionPromptScheduler do
  let(:tenant) { create(:tenant, :confirmed) }
  let(:source) do
    create(:source, :configured, tenant: tenant, responsibility_key: "marketing_strategy")
  end

  describe ".call" do
    it "creates a pending SubmissionPrompt for each Request belonging to the Source" do
      r1 = create(:request, tenant: tenant, source: source, metric_key: "m1", cadence: "monthly")
      r2 = create(:request, tenant: tenant, source: source, metric_key: "m2", cadence: "quarterly")

      expect {
        described_class.call(source: source)
      }.to change(SubmissionPrompt, :count).by(2)

      expect(SubmissionPrompt.where(request: r1).count).to eq(1)
      expect(SubmissionPrompt.where(request: r2).count).to eq(1)
    end

    it "schedules monthly prompts for the 1st of the next month" do
      travel_to(Time.zone.parse("2026-05-15 10:00:00")) do
        request = create(:request, tenant: tenant, source: source, metric_key: "m1", cadence: "monthly")
        described_class.call(source: source)
        prompt = SubmissionPrompt.where(request: request).first
        expect(prompt.scheduled_for.in_time_zone(tenant.time_zone).to_date)
          .to eq(Date.new(2026, 6, 1))
      end
    end

    it "schedules quarterly prompts for the 1st of the next calendar quarter" do
      travel_to(Time.zone.parse("2026-05-15 10:00:00")) do
        request = create(:request, tenant: tenant, source: source, metric_key: "m1", cadence: "quarterly")
        described_class.call(source: source)
        prompt = SubmissionPrompt.where(request: request).first
        # Q2 is Apr-Jun → next quarter starts Jul 1
        expect(prompt.scheduled_for.in_time_zone(tenant.time_zone).to_date)
          .to eq(Date.new(2026, 7, 1))
      end
    end

    it "is idempotent — calling twice does not double-schedule" do
      create(:request, tenant: tenant, source: source, metric_key: "m1", cadence: "monthly")
      described_class.call(source: source)
      expect {
        described_class.call(source: source)
      }.not_to change(SubmissionPrompt, :count)
    end
  end
end
