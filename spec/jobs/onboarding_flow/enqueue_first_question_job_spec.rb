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
      it "enqueues the question email for immediate delivery (no wait_until)" do
        expect {
          described_class.perform_now(tenant_id: tenant.id)
        }
          .to(have_enqueued_mail(OnboardingMailer, :question_email))

        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |j|
          j[:job] == ActionMailer::MailDeliveryJob
        }
        expect(enqueued).not_to(be_nil)
        # No wait_until — the first question email sends immediately.
        expect(enqueued[:at]).to(be_nil)
      end

      it "sends immediately regardless of the business-hours envelope (e.g. weekends)" do
        saturday_noon_utc = Time.zone.parse("2026-05-09 12:00:00 UTC")

        travel_to(saturday_noon_utc) do
          expect(OnboardingFlow::Scheduling).not_to(receive(:next_business_window))

          expect {
            described_class.perform_now(tenant_id: tenant.id)
          }
            .to(have_enqueued_mail(OnboardingMailer, :question_email))

          question = tenant.tenant_questions.order(:position).first.reload
          # sent_at is "now" (Saturday noon UTC), not the next business window.
          expect(question.sent_at).to(eq(saturday_noon_utc))
        end
      end

      it "ignores tenant.first_question_delay_minutes (always immediate)" do
        tenant.update!(first_question_delay_minutes: 999)

        freeze_time do
          expect {
            described_class.perform_now(tenant_id: tenant.id)
          }
            .to(have_enqueued_mail(OnboardingMailer, :question_email))

          question = tenant.tenant_questions.order(:position).first.reload
          expect(question.sent_at).to(eq(Time.current))
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
