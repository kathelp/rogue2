require "rails_helper"

RSpec.describe Submission do
  let(:tenant) { create(:tenant, :confirmed) }
  let(:source) { create(:source, :configured, tenant: tenant, responsibility_key: "marketing_strategy") }
  let(:request_record) { create(:request, tenant: tenant, source: source, metric_key: "strategy_summary", cadence: "monthly") }
  let(:prompt) { create(:submission_prompt, tenant: tenant, request: request_record) }
  let(:contact) { create(:contact, tenant: tenant) }

  it "is valid with the required associations and value" do
    submission = build(:submission,
                       tenant: tenant,
                       request: request_record,
                       submission_prompt: prompt,
                       submitted_by_contact: contact,
                       value: 42_500.0,
                       period_starting: Date.new(2026, 5, 1),
                       submitted_at: Time.current)
    expect(submission).to be_valid
  end

  it "is invalid without value" do
    s = build(:submission, value: nil)
    expect(s).not_to be_valid
    expect(s.errors[:value]).to be_present
  end

  it "is invalid with negative value" do
    s = build(:submission, value: -1.0)
    expect(s).not_to be_valid
  end

  it "is invalid without period_starting" do
    s = build(:submission, period_starting: nil)
    expect(s).not_to be_valid
  end

  it "is invalid without submitted_at" do
    s = build(:submission, submitted_at: nil)
    expect(s).not_to be_valid
  end

  it "belongs_to request, submission_prompt, submitted_by_contact, tenant" do
    expect(described_class.reflect_on_association(:request)).not_to be_nil
    expect(described_class.reflect_on_association(:submission_prompt)).not_to be_nil
    expect(described_class.reflect_on_association(:submitted_by_contact)).not_to be_nil
    expect(described_class.reflect_on_association(:tenant)).not_to be_nil
  end

  describe ".for_period scope" do
    it "filters by period_starting" do
      may = create(:submission, tenant: tenant, request: request_record, submission_prompt: prompt,
                   submitted_by_contact: contact, period_starting: Date.new(2026, 5, 1))
      _june = create(:submission, tenant: tenant, request: request_record,
                     submission_prompt: create(:submission_prompt, tenant: tenant, request: request_record),
                     submitted_by_contact: contact, period_starting: Date.new(2026, 6, 1))
      result = described_class.for_period(Date.new(2026, 5, 1))
      expect(result).to include(may)
      expect(result.count).to eq(1)
    end
  end
end
