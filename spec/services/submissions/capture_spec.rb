require "rails_helper"

RSpec.describe Submissions::Capture do
  let(:tenant) { create(:tenant, :confirmed) }
  let(:contact) { create(:contact, tenant: tenant) }
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
    create(
      :request,
      tenant: tenant,
      source: source,
      metric_key: "strategy_summary",
      cadence: "monthly"
    )
  end

  let(:prompt) do
    create(
      :submission_prompt,
      tenant: tenant,
      request: request_record,
      status: "sent",
      scheduled_for: Time.zone.parse("2026-05-01 10:00:00")
    )
  end

  describe ".call" do
    it "creates a Submission row and returns success" do
      result = described_class.call(prompt: prompt, contact: contact, value: 42_500.0, notes: "May numbers")
      expect(result.success?).to(be(true))
      expect(result.submission).to(be_a(Submission))
      expect(Submission.count).to(eq(1))
      expect(result.submission.value).to(eq(42_500.0))
      expect(result.submission.notes).to(eq("May numbers"))
    end

    it "marks the prompt :fulfilled with fulfilled_at set" do
      freeze_time do
        described_class.call(prompt: prompt, contact: contact, value: 1.0)
        prompt.reload
        expect(prompt.status).to(eq("fulfilled"))
        expect(prompt.fulfilled_at).to(be_within(1.second).of(Time.current))
      end
    end

    it "sets period_starting from prompt.scheduled_for in tenant TZ" do
      result = described_class.call(prompt: prompt, contact: contact, value: 1.0)
      expect(result.submission.period_starting).to(eq(Date.new(2026, 5, 1)))
    end

    it "records a submission.captured FlowEvent" do
      expect {
        described_class.call(prompt: prompt, contact: contact, value: 1.0)
      }
        .to(change { FlowEvent.where(event_type: "submission.captured").count }.by(1))
    end

    context("when prompt is already :fulfilled (idempotency)") do
      before { prompt.update!(status: :fulfilled, fulfilled_at: 1.hour.ago) }

      it "returns a result with success=false and :already_submitted error" do
        result = described_class.call(prompt: prompt, contact: contact, value: 99.0)
        expect(result.success?).to(be(false))
        expect(result.error).to(eq(:already_submitted))
      end

      it "does not create a duplicate Submission" do
        expect {
          described_class.call(prompt: prompt, contact: contact, value: 99.0)
        }
          .not_to(change(Submission, :count))
      end
    end

    context("with invalid value") do
      it "returns a result with success=false and :invalid_value" do
        result = described_class.call(prompt: prompt, contact: contact, value: -1.0)
        expect(result.success?).to(be(false))
        expect(result.error).to(eq(:invalid_value))
      end

      it "rolls back, leaving the prompt :sent and no Submission row" do
        expect {
          described_class.call(prompt: prompt, contact: contact, value: nil)
        }
          .not_to(change(Submission, :count))
        expect(prompt.reload.status).to(eq("sent"))
      end
    end
  end
end
