require "rails_helper"

RSpec.describe WeeklyDigestJob do
  include ActiveJob::TestHelper

  describe "#perform" do
    context "tenants confirmed >= 7 days" do
      let!(:eligible_tenant) do
        create(:tenant, :active, gm_email: "jane@smithtoyota.com",
               confirmed_at: 8.days.ago)
      end
      let!(:fresh_tenant) do
        # Confirmed only 2 days ago — not eligible
        create(:tenant, :confirmed, gm_email: "alex@othertoyota.com",
               confirmed_at: 2.days.ago)
      end

      it "queues a digest mail to each eligible tenant's GM" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(ActionMailer::Base.deliveries, :count).by(1)

        expect(ActionMailer::Base.deliveries.last.to).to eq([ "jane@smithtoyota.com" ])
      end

      it "does NOT send to tenants confirmed less than 7 days ago" do
        perform_enqueued_jobs { described_class.perform_now }
        recipients = ActionMailer::Base.deliveries.flat_map(&:to)
        expect(recipients).not_to include("alex@othertoyota.com")
      end

      it "creates a WeeklyDigestDelivery row for each tenant sent to" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(WeeklyDigestDelivery, :count).by(1)
      end
    end

    context "idempotency on (tenant_id, week_starting)" do
      let!(:tenant) do
        create(:tenant, :active, gm_email: "jane@smithtoyota.com",
               confirmed_at: 8.days.ago)
      end

      it "does not double-send if run twice in the same week" do
        perform_enqueued_jobs { described_class.perform_now }
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.not_to change(ActionMailer::Base.deliveries, :count)
      end

      it "WeeklyDigestDelivery row count stays at 1 across re-runs" do
        perform_enqueued_jobs { described_class.perform_now }
        perform_enqueued_jobs { described_class.perform_now }
        expect(WeeklyDigestDelivery.where(tenant: tenant).count).to eq(1)
      end
    end

    context "AC-ASYNC-3: empty-state digest still ships" do
      let!(:tenant) do
        create(:tenant, :active, gm_email: "jane@smithtoyota.com",
               confirmed_at: 8.days.ago)
      end

      it "queues a digest even when the tenant has no responsibilities" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(ActionMailer::Base.deliveries, :count).by(1)
        body = ActionMailer::Base.deliveries.last.html_part.body.decoded
        expect(body).to match(/no submissions/i)
      end
    end
  end
end
