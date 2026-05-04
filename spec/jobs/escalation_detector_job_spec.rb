require "rails_helper"

RSpec.describe EscalationDetectorJob do
  include ActiveJob::TestHelper

  let(:tenant) do
    create(:tenant, :confirmed,
           dealership_name: "Smith Toyota", gm_email: "jane@smithtoyota.com",
           time_zone: "America/New_York", onboarding_token: "tok123abc")
  end
  let(:contact) { create(:contact, tenant: tenant, email: "alex@smithtoyota.com") }
  let(:source) do
    create(:source, :configured, tenant: tenant,
           responsibility_key: "marketing_strategy", configured_by_contact: contact)
  end
  let(:request_record) do
    create(:request, tenant: tenant, source: source,
           metric_key: "strategy_summary", cadence: "monthly")
  end
  let(:question) do
    create(:tenant_question, tenant: tenant, key: "marketing_strategy",
           prompt: "Who controls your marketing strategy?")
  end
  let!(:responsibility) do
    create(:responsibility, tenant: tenant, tenant_question: question,
           primary_contact: contact, fallback_contact_emails: [])
  end

  describe "#perform" do
    let!(:prompt) do
      create(:submission_prompt, tenant: tenant, request: request_record,
             status: "sent",
             scheduled_for: Time.zone.parse("2026-05-01 09:00:00"),
             sent_at: Time.zone.parse("2026-05-01 09:00:00"))
    end

    context "when due_soon window is open" do
      it "records an escalation.due_soon FlowEvent and queues a mailer" do
        travel_to(Time.zone.parse("2026-05-29 10:00:00")) do
          expect {
            perform_enqueued_jobs { described_class.perform_now }
          }.to change { FlowEvent.where(event_type: "escalation.due_soon").count }.by(1)
            .and change(ActionMailer::Base.deliveries, :count).by(1)
        end
      end

      it "is idempotent — rerunning the same hour adds no second event/mail" do
        travel_to(Time.zone.parse("2026-05-29 10:00:00")) do
          perform_enqueued_jobs { described_class.perform_now }
          expect {
            perform_enqueued_jobs { described_class.perform_now }
          }.not_to change(ActionMailer::Base.deliveries, :count)
        end
      end
    end

    context "when no escalation is needed" do
      it "no FlowEvent, no mail" do
        travel_to(Time.zone.parse("2026-05-15 10:00:00")) do
          expect {
            perform_enqueued_jobs { described_class.perform_now }
          }.not_to change(FlowEvent, :count)
        end
      end
    end

    context "when prompt is :fulfilled" do
      it "skips fulfilled prompts even if past period_end" do
        prompt.update!(status: :fulfilled, fulfilled_at: 1.day.ago)
        travel_to(Time.zone.parse("2026-06-15 10:00:00")) do
          expect {
            perform_enqueued_jobs { described_class.perform_now }
          }.not_to change(FlowEvent, :count)
        end
      end
    end

    context "full ladder traversal across time" do
      let!(:responsibility_with_fallbacks) do
        responsibility.update!(fallback_contact_emails: [ "taylor@smithtoyota.com" ])
        responsibility
      end

      it "walks due_soon → overdue → fallback → gm_nudge across detector runs" do
        # due_soon
        travel_to(Time.zone.parse("2026-05-29 10:00:00")) do
          perform_enqueued_jobs { described_class.perform_now }
        end
        expect(FlowEvent.where(event_type: "escalation.due_soon").count).to eq(1)

        # overdue
        travel_to(Time.zone.parse("2026-06-03 10:00:00")) do
          perform_enqueued_jobs { described_class.perform_now }
        end
        expect(FlowEvent.where(event_type: "escalation.overdue").count).to eq(1)

        # fallback_fanout
        travel_to(Time.zone.parse("2026-06-07 10:00:00")) do
          perform_enqueued_jobs { described_class.perform_now }
        end
        expect(FlowEvent.where(event_type: "escalation.fallback_fanout").count).to eq(1)

        # gm_nudge
        travel_to(Time.zone.parse("2026-06-12 10:00:00")) do
          perform_enqueued_jobs { described_class.perform_now }
        end
        expect(FlowEvent.where(event_type: "escalation.gm_nudge").count).to eq(1)

        # 4 mails total across the ladder
        expect(ActionMailer::Base.deliveries.count).to eq(4)
      end
    end
  end
end
