require "rails_helper"

RSpec.describe WeeklyDigestDelivery do
  let(:tenant) { create(:tenant) }

  it "is valid with tenant + week_starting + delivered_at" do
    delivery = described_class.new(tenant: tenant, week_starting: Date.current, delivered_at: Time.current)
    expect(delivery).to(be_valid)
  end

  it "is invalid without week_starting" do
    expect(described_class.new(tenant: tenant, delivered_at: Time.current)).not_to(be_valid)
  end

  it "enforces a unique (tenant_id, week_starting) constraint" do
    described_class.create!(tenant: tenant, week_starting: Date.current, delivered_at: Time.current)

    error = begin
      described_class.create!(tenant: tenant, week_starting: Date.current, delivered_at: Time.current)
      nil
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      e
    end

    expect(error).to(be_a(ActiveRecord::RecordInvalid).or(be_a(ActiveRecord::RecordNotUnique)))
  end
end
