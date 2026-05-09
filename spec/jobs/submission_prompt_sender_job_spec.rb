require "rails_helper"

RSpec.describe SubmissionPromptSenderJob do
  include(ActiveJob::TestHelper)

  let(:tenant) { create(:tenant, :confirmed) }
  let(:contact) { create(:contact, tenant: tenant, email: "alex@smithtoyota.com") }
  let(:source) do
    create(
      :source,
      :configured,
      tenant: tenant,
      responsibility_key: "marketing_strategy",
      configured_by_contact: contact
    )
  end

  let(:request_record) do
    create(:request, tenant: tenant, source: source, metric_key: "strategy_summary", cadence: "monthly")
  end

  describe "#perform" do
    context("with a pending due prompt and a form-method Source") do
      let!(:prompt) do
        create(
          :submission_prompt,
          tenant: tenant,
          request: request_record,
          status: "pending",
          scheduled_for: 2.hours.ago
        )
      end

      it "transitions the prompt to :sent" do
        described_class.perform_now
        expect(prompt.reload.status).to(eq("sent"))
      end

      it "sets sent_at" do
        freeze_time do
          described_class.perform_now
          expect(prompt.reload.sent_at).to(be_within(1.second).of(Time.current))
        end
      end

      it "queues a prompt_email to the configured_by_contact" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }
          .to(change(ActionMailer::Base.deliveries, :count).by(1))

        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to(eq(["alex@smithtoyota.com"]))
        expect(mail.subject).to(include("strategy summary"))
      end

      it "records a submission.prompt_sent FlowEvent" do
        expect {
          described_class.perform_now
        }
          .to(change { FlowEvent.where(event_type: "submission.prompt_sent").count }.by(1))
      end
    end

    context("with a pending prompt scheduled in the future") do
      let!(:future_prompt) do
        create(
          :submission_prompt,
          tenant: tenant,
          request: request_record,
          status: "pending",
          scheduled_for: 1.day.from_now
        )
      end

      it "leaves the prompt :pending and sends no mail" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }
          .not_to(change(ActionMailer::Base.deliveries, :count))
        expect(future_prompt.reload.status).to(eq("pending"))
      end
    end

    context("with an already-sent prompt (idempotency)") do
      let!(:sent_prompt) do
        create(
          :submission_prompt,
          tenant: tenant,
          request: request_record,
          status: "sent",
          scheduled_for: 2.hours.ago,
          sent_at: 1.hour.ago
        )
      end

      it "does not re-send" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }
          .not_to(change(ActionMailer::Base.deliveries, :count))
      end
    end

    context("with a fulfilled prompt") do
      let!(:fulfilled_prompt) do
        create(
          :submission_prompt,
          tenant: tenant,
          request: request_record,
          status: "fulfilled",
          scheduled_for: 2.hours.ago
        )
      end

      it "does not re-send" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }
          .not_to(change(ActionMailer::Base.deliveries, :count))
      end
    end

    context("with a Source whose submission_method is :csv (parked state)") do
      let(:csv_source) do
        create(
          :source,
          tenant: tenant,
          responsibility_key: "dealer_website",
          submission_method: "csv",
          configured_at: Time.current,
          configured_by_contact: contact
        )
      end

      let(:csv_request) do
        create(:request, tenant: tenant, source: csv_source, metric_key: "website_traffic", cadence: "monthly")
      end

      let!(:csv_prompt) do
        create(
          :submission_prompt,
          tenant: tenant,
          request: csv_request,
          status: "pending",
          scheduled_for: 2.hours.ago
        )
      end

      it "queues an adapter_pending_email instead" do
        perform_enqueued_jobs { described_class.perform_now }
        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject).to(match(/adapter|CSV|csv/i))
      end

      it "still flips the prompt to :sent (so we don't loop)" do
        described_class.perform_now
        expect(csv_prompt.reload.status).to(eq("sent"))
      end
    end
  end
end
