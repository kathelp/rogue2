require "rails_helper"

RSpec.describe FlowEvent, type: :model do
  subject(:flow_event) { build(:flow_event) }

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  it { is_expected.to belong_to(:tenant).optional }

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  it { is_expected.to validate_presence_of(:event_type) }
  it { is_expected.to validate_presence_of(:occurred_at) }

  # --------------------------------------------------------------------------
  # FlowEvent.record!
  # --------------------------------------------------------------------------
  describe ".record!" do
    let(:tenant) { create(:tenant) }

    it "creates a FlowEvent row" do
      expect {
        FlowEvent.record!(event_type: "tenant.seeded", tenant: tenant)
      }.to change(FlowEvent, :count).by(1)
    end

    it "sets occurred_at to Time.current by default" do
      now = Time.current
      travel_to(now) do
        event = FlowEvent.record!(event_type: "tenant.seeded", tenant: tenant)
        expect(event.occurred_at).to be_within(1.second).of(now)
      end
    end

    it "defaults payload to empty hash" do
      event = FlowEvent.record!(event_type: "tenant.seeded", tenant: tenant)
      expect(event.payload).to eq({})
    end

    it "stores custom payload" do
      event = FlowEvent.record!(
        event_type: "tenant.confirmed",
        tenant: tenant,
        payload: { ip: "127.0.0.1" }
      )
      expect(event.payload).to eq({ "ip" => "127.0.0.1" })
    end

    it "sets subject_type and subject_id from subject argument" do
      event = FlowEvent.record!(
        event_type: "tenant.confirmed",
        tenant: tenant,
        subject: tenant
      )
      expect(event.subject_type).to eq("Tenant")
      expect(event.subject_id).to eq(tenant.id)
    end

    it "uses Current.tenant when no tenant arg provided" do
      Current.tenant = tenant
      event = FlowEvent.record!(event_type: "tenant.seeded")
      expect(event.tenant).to eq(tenant)
    ensure
      Current.tenant = nil
    end
  end
end
