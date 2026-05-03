require "rails_helper"

RSpec.describe OnboardingFlow::EnqueueNextQuestionJob, type: :job do
  include ActiveJob::TestHelper

  let(:tenant) { create(:tenant, :confirmed, time_zone: "America/New_York", next_question_delay_hours: 24) }

  before do
    Rogue::QuestionCatalog::Marketing::V1.materialize_for(tenant: tenant)
  end

  describe "#perform" do
    context "with an explicit wait_hours" do
      it "uses the provided wait_hours to compute delivery time" do
        freeze_time do
          expected_target = Time.current + 12.hours
          allow(OnboardingFlow::Scheduling).to receive(:next_business_window)
            .with(after: expected_target, time_zone: "America/New_York")
            .and_return(expected_target)

          expect {
            described_class.perform_now(tenant_id: tenant.id, wait_hours: 12)
          }.to have_enqueued_mail(OnboardingMailer, :question_email)
        end
      end
    end

    context "without explicit wait_hours" do
      it "defaults to tenant.next_question_delay_hours" do
        freeze_time do
          expected_target = Time.current + 24.hours
          allow(OnboardingFlow::Scheduling).to receive(:next_business_window)
            .with(after: expected_target, time_zone: "America/New_York")
            .and_return(expected_target)

          expect {
            described_class.perform_now(tenant_id: tenant.id)
          }.to have_enqueued_mail(OnboardingMailer, :question_email)
        end
      end
    end

    context "when there is no pending question" do
      before do
        tenant.tenant_questions.update_all(status: "answered")
      end

      it "returns early and does not enqueue any mail" do
        expect {
          described_class.perform_now(tenant_id: tenant.id)
        }.not_to have_enqueued_mail
      end
    end
  end
end
