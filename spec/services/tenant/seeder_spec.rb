require "rails_helper"

RSpec.describe Tenant::Seeder, type: :service do
  let(:valid_params) do
    {
      dealership_name: "Smith Toyota",
      gm_name: "Jane Smith",
      gm_email: "jane@smithtoyota.com"
    }
  end

  describe ".call" do
    context "with valid params" do
      it "creates a Tenant in pending_confirm status" do
        result = described_class.call(**valid_params)

        expect(result.success?).to be true
        expect(result.tenant).to be_persisted
        expect(result.tenant.status).to eq("pending_confirm")
      end

      it "sets confirmation_sent_at on the tenant" do
        freeze_time do
          result = described_class.call(**valid_params)

          expect(result.tenant.confirmation_sent_at).to be_within(1.second).of(Time.current)
        end
      end

      it "enqueues a confirmation email via OnboardingMailer" do
        expect {
          described_class.call(**valid_params)
        }.to have_enqueued_mail(OnboardingMailer, :confirmation_email)
      end

      it "records a tenant.seeded FlowEvent" do
        expect {
          described_class.call(**valid_params)
        }.to change(FlowEvent, :count).by(1)

        event = FlowEvent.last
        expect(event.event_type).to eq("tenant.seeded")
        expect(event.subject_type).to eq("Tenant")
      end

      it "normalizes the gm_email on the tenant" do
        result = described_class.call(**valid_params.merge(gm_email: "  Jane@SmithToyota.com  "))

        expect(result.tenant.gm_email).to eq("jane@smithtoyota.com")
      end
    end

    context "with missing dealership_name" do
      it "returns a failure result" do
        result = described_class.call(dealership_name: "", gm_name: "Jane Smith", gm_email: "jane@smithtoyota.com")

        expect(result.success?).to be false
        expect(result.errors).to include(a_string_matching(/Dealership name/))
      end

      it "does not enqueue any mail" do
        expect {
          described_class.call(dealership_name: "", gm_name: "Jane Smith", gm_email: "jane@smithtoyota.com")
        }.not_to have_enqueued_mail
      end
    end

    context "with missing gm_email" do
      it "returns a failure result with errors" do
        result = described_class.call(dealership_name: "Smith Toyota", gm_name: "Jane Smith", gm_email: "")

        expect(result.success?).to be false
        expect(result.errors).not_to be_empty
      end
    end

    context "with a duplicate gm_email" do
      before { create(:tenant, gm_email: "jane@smithtoyota.com") }

      it "returns a failure result" do
        result = described_class.call(**valid_params)

        expect(result.success?).to be false
        expect(result.tenant).not_to be_persisted
      end
    end
  end
end
