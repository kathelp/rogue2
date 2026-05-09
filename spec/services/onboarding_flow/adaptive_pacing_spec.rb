require "rails_helper"

RSpec.describe OnboardingFlow::AdaptivePacing do
  let(:base_time) { Time.zone.parse("2026-05-04 10:00:00") }

  describe ".next_wait_hours" do
    context("when GM replies in < 1 hour") do
      it "returns 12 hours" do
        sent_at = base_time
        reply_at = base_time + 30.minutes

        result = described_class.next_wait_hours(
          question_sent_at: sent_at,
          reply_received_at: reply_at
        )
        expect(result).to(eq(12))
      end
    end

    context("when GM replies between 1 and 24 hours") do
      it "returns 24 hours" do
        sent_at = base_time
        reply_at = base_time + 6.hours

        result = described_class.next_wait_hours(
          question_sent_at: sent_at,
          reply_received_at: reply_at
        )
        expect(result).to(eq(24))
      end
    end

    context("when GM replies between 24 and 72 hours") do
      it "returns 48 hours" do
        sent_at = base_time
        reply_at = base_time + 50.hours

        result = described_class.next_wait_hours(
          question_sent_at: sent_at,
          reply_received_at: reply_at
        )
        expect(result).to(eq(48))
      end
    end

    context("when GM has been silent for >= 72 hours") do
      it "returns nil (do not schedule)" do
        sent_at = base_time
        reply_at = base_time + 80.hours

        result = described_class.next_wait_hours(
          question_sent_at: sent_at,
          reply_received_at: reply_at
        )
        expect(result).to(be_nil)
      end
    end

    context("with pathological clock skew (negative elapsed)") do
      it "handles negative elapsed gracefully — treats as < 1h" do
        # sent in the future (clock skew)
        sent_at = base_time + 5.minutes
        # reply before sent_at
        reply_at = base_time

        result = described_class.next_wait_hours(
          question_sent_at: sent_at,
          reply_received_at: reply_at
        )
        # Negative elapsed clamps to 0, which is < 1h → 12h
        expect(result).to(eq(12))
      end
    end

    context("when question_sent_at is nil (first question scenario)") do
      it "defaults to 24 hours" do
        result = described_class.next_wait_hours(
          question_sent_at: nil,
          reply_received_at: base_time
        )
        expect(result).to(eq(24))
      end
    end
  end
end
