require "rails_helper"

RSpec.describe OnboardingFlow::EnqueueFirstQuestionJob, type: :job do
  include(ActiveJob::TestHelper)

  let(:tenant) { create(:tenant, :confirmed, time_zone: "America/New_York", first_question_delay_minutes: 60) }

  before do
    # Materialize catalog so there is a pending question available.
    Rogue::QuestionCatalog::Marketing::V1.materialize_for(tenant: tenant)
  end

  describe "#perform" do
    context("when tenant is confirmed with a pending question") do
      it "enqueues the question email to deliver after first_question_delay_minutes" do
        freeze_time do
          expected_target = Time.current + 60.minutes
          allow(OnboardingFlow::Scheduling).to(
            receive(:next_business_window)
              .with(after: expected_target, time_zone: "America/New_York")
              .and_return(expected_target)
          )

          expect {
            described_class.perform_now(tenant_id: tenant.id)
          }
            .to(have_enqueued_mail(OnboardingMailer, :question_email))
        end
      end

      it "bumps deliver_at to the next business window when target falls outside hours" do
        # Saturday at noon UTC — should bump to Monday 9:30am ET
        # Saturday
        saturday_noon_utc = Time.zone.parse("2026-05-09 12:00:00 UTC")
        monday_open_et = ActiveSupport::TimeZone["America/New_York"].local(2026, 5, 11, 9, 30, 0)

        travel_to(saturday_noon_utc) do
          # 60 minutes after Saturday noon = Saturday 1pm; outside business hours
          expect {
            described_class.perform_now(tenant_id: tenant.id)
          }
            .to(have_enqueued_mail(OnboardingMailer, :question_email))

          question = tenant.tenant_questions.order(:position).first
          question.reload
          # The sent_at should be >= Monday 9:30am ET (next business window)
          expect(question.sent_at.in_time_zone("America/New_York").hour).to(eq(9))
          expect(question.sent_at.in_time_zone("America/New_York").min).to(eq(30))
        end
      end

      it "updates question.status to sent and sets outbound_message_id" do
        described_class.perform_now(tenant_id: tenant.id)
        question = tenant.tenant_questions.order(:position).first.reload
        expect(question.status).to(eq("sent"))
        expect(question.outbound_message_id).to(be_present)
        expect(question.outbound_message_id).to(match(/\A<onboarding-q-/))
      end

      it "sets question.sent_at" do
        described_class.perform_now(tenant_id: tenant.id)
        question = tenant.tenant_questions.order(:position).first.reload
        expect(question.sent_at).to(be_present)
      end

      it "records a question.sent FlowEvent" do
        expect {
          described_class.perform_now(tenant_id: tenant.id)
        }
          .to(change(FlowEvent, :count).by(1))

        event = FlowEvent.last
        expect(event.event_type).to(eq("question.sent"))
        expect(event.tenant_id).to(eq(tenant.id))
        expect(event.payload["message_id"]).to(be_present)
        expect(event.payload["deliver_at"]).to(be_present)
      end
    end

    context("when tenant is not confirmed") do
      # status: pending_confirm
      let(:unconfirmed_tenant) { create(:tenant) }

      it "returns early and does not enqueue any mail" do
        expect {
          described_class.perform_now(tenant_id: unconfirmed_tenant.id)
        }
          .not_to(have_enqueued_mail)
      end
    end

    context("when there is no pending question") do
      before do
        # Mark all questions as answered
        tenant.tenant_questions.update_all(status: "answered")
      end

      it "returns early and does not enqueue any mail" do
        expect {
          described_class.perform_now(tenant_id: tenant.id)
        }
          .not_to(have_enqueued_mail)
      end
    end
  end
end
