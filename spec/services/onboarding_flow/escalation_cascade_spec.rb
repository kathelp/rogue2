require "rails_helper"

RSpec.describe OnboardingFlow::EscalationCascade do
  let(:tenant) do
    create(
      :tenant,
      :confirmed,
      dealership_name: "Smith Toyota",
      gm_email: "jane@smithtoyota.com",
      time_zone: "America/New_York"
    )
  end

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
    create(
      :request,
      tenant: tenant,
      source: source,
      metric_key: "strategy_summary",
      cadence: "monthly"
    )
  end

  let(:question) do
    create(
      :tenant_question,
      tenant: tenant,
      key: "marketing_strategy",
      prompt: "Who controls your marketing strategy?"
    )
  end

  let(:fallback_emails) { [] }
  let!(:responsibility) do
    create(
      :responsibility,
      tenant: tenant,
      tenant_question: question,
      primary_contact: contact,
      fallback_contact_emails: fallback_emails
    )
  end

  # Period boundaries used in these tests:
  #   prompt.scheduled_for = May 1, 2026 → period covers May 1–31
  #   period_end = May 31, 2026 (end-of-month in tenant TZ)
  let(:scheduled_for) { Time.zone.parse("2026-05-01 09:00:00") }
  let(:prompt) do
    create(
      :submission_prompt,
      tenant: tenant,
      request: request_record,
      status: "sent",
      scheduled_for: scheduled_for,
      sent_at: scheduled_for
    )
  end

  describe ".next_action_for" do
    context("before the due-soon window opens") do
      it "returns nil when there's plenty of time before period end" do
        # 10 days before period end (May 21)
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-05-21 10:00:00"))
        expect(result).to(be_nil)
      end
    end

    context("when due-soon window opens (3 days before period end)") do
      it "returns severity :due_soon for the primary contact" do
        # May 29 = period_end - 3 days
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-05-29 10:00:00"))
        expect(result).not_to(be_nil)
        expect(result.severity).to(eq(:due_soon))
        expect(result.recipient_email).to(eq("alex@smithtoyota.com"))
      end

      it "returns nil when due_soon FlowEvent already exists" do
        FlowEvent.record!(
          event_type: "escalation.due_soon",
          tenant: tenant,
          subject: prompt,
          payload: {severity: "due_soon"}
        )
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-05-29 10:00:00"))
        # No new action until the next severity threshold (overdue) is reached
        expect(result).to(be_nil)
      end
    end

    context("when overdue window opens (3 days past period end)") do
      before do
        FlowEvent.record!(
          event_type: "escalation.due_soon",
          tenant: tenant,
          subject: prompt,
          payload: {severity: "due_soon"},
          occurred_at: Time.zone.parse("2026-05-29 10:00:00")
        )
      end

      it "returns severity :overdue for the primary contact" do
        # June 3 = period_end + 3 days
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-03 10:00:00"))
        expect(result.severity).to(eq(:overdue))
        expect(result.recipient_email).to(eq("alex@smithtoyota.com"))
      end
    end

    context("when fallback fan-out window opens") do
      let(:fallback_emails) { ["taylor@smithtoyota.com", "casey@smithtoyota.com"] }

      before do
        FlowEvent.record!(
          event_type: "escalation.due_soon",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-05-29 10:00:00")
        )
        FlowEvent.record!(
          event_type: "escalation.overdue",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-06-03 10:00:00")
        )
      end

      it "returns severity :fallback_fanout with the first fallback when grace passes" do
        # June 7 = overdue + 4 days
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-07 10:00:00"))
        expect(result.severity).to(eq(:fallback_fanout))
        expect(result.recipient_email).to(eq("taylor@smithtoyota.com"))
        expect(result.payload[:fallback_index]).to(eq(0))
      end

      it "returns the second fallback after the first has been pinged" do
        FlowEvent.record!(
          event_type: "escalation.fallback_fanout",
          tenant: tenant,
          subject: prompt,
          payload: {fallback_index: 0, fallback_email: "taylor@smithtoyota.com"},
          occurred_at: Time.zone.parse("2026-06-07 10:00:00")
        )
        # June 11 = first fallback + 4 days
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-11 10:00:00"))
        expect(result.severity).to(eq(:fallback_fanout))
        expect(result.recipient_email).to(eq("casey@smithtoyota.com"))
        expect(result.payload[:fallback_index]).to(eq(1))
      end
    end

    context("when GM nudge window opens (after fallbacks exhausted)") do
      let(:fallback_emails) { ["taylor@smithtoyota.com"] }

      before do
        FlowEvent.record!(
          event_type: "escalation.due_soon",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-05-29 10:00:00")
        )
        FlowEvent.record!(
          event_type: "escalation.overdue",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-06-03 10:00:00")
        )
        FlowEvent.record!(
          event_type: "escalation.fallback_fanout",
          tenant: tenant,
          subject: prompt,
          payload: {fallback_index: 0, fallback_email: "taylor@smithtoyota.com"},
          occurred_at: Time.zone.parse("2026-06-07 10:00:00")
        )
      end

      it "returns severity :gm_nudge when grace_days past last fallback" do
        # June 12 = last fallback + 5 days
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-12 10:00:00"))
        expect(result.severity).to(eq(:gm_nudge))
        expect(result.recipient_email).to(eq("jane@smithtoyota.com"))
      end

      it "carries the responsibility chain (primary + fallbacks) on the gm_nudge payload for CCing" do
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-12 10:00:00"))
        expect(result.payload[:primary_email]).to(eq("alex@smithtoyota.com"))
        expect(result.payload[:fallback_chain]).to(eq(["taylor@smithtoyota.com"]))
      end

      it "returns nil after GM nudge has fired (one-shot per period)" do
        FlowEvent.record!(
          event_type: "escalation.gm_nudge",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-06-12 10:00:00")
        )
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-20 10:00:00"))
        expect(result).to(be_nil)
      end
    end

    context("when responsibility has no fallbacks") do
      let(:fallback_emails) { [] }

      before do
        FlowEvent.record!(
          event_type: "escalation.due_soon",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-05-29 10:00:00")
        )
        FlowEvent.record!(
          event_type: "escalation.overdue",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-06-03 10:00:00")
        )
      end

      it "skips fallback fan-out and goes straight to gm_nudge" do
        # 5 days after overdue
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-08 10:00:00"))
        expect(result.severity).to(eq(:gm_nudge))
        expect(result.recipient_email).to(eq("jane@smithtoyota.com"))
      end
    end

    # FEAT-006 / TASK-008 — gating: filter unverified Contacts from fallback fan-out
    context("gating: unverified Contacts are filtered from fallback fan-out") do
      let(:fallback_emails) {
        ["unverified@smithtoyota.com", "verified@smithtoyota.com", "external@vendor.com"]
      }

      before do
        # Existing Contact records: one unverified (default factory), one verified.
        # "external@vendor.com" intentionally has NO Contact row — legacy GM-typed
        # fallback that must pass through unchanged.
        create(:contact, tenant: tenant, email: "unverified@smithtoyota.com")
        create(:contact, :verified, tenant: tenant, email: "verified@smithtoyota.com")

        FlowEvent.record!(
          event_type: "escalation.due_soon",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-05-29 10:00:00")
        )
        FlowEvent.record!(
          event_type: "escalation.overdue",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-06-03 10:00:00")
        )
      end

      it "skips the unverified Contact and selects the verified Contact as first fallback" do
        result = described_class.next_action_for(
          prompt: prompt,
          now: Time.zone.parse("2026-06-07 10:00:00")
        )
        expect(result.severity).to(eq(:fallback_fanout))
        expect(result.recipient_email).to(eq("verified@smithtoyota.com"))
      end

      it "passes through emails not in the contacts table (legacy raw strings)" do
        FlowEvent.record!(
          event_type: "escalation.fallback_fanout",
          tenant: tenant,
          subject: prompt,
          payload: {fallback_index: 0, fallback_email: "verified@smithtoyota.com"},
          occurred_at: Time.zone.parse("2026-06-07 10:00:00")
        )
        result = described_class.next_action_for(
          prompt: prompt,
          now: Time.zone.parse("2026-06-11 10:00:00")
        )
        expect(result.severity).to(eq(:fallback_fanout))
        expect(result.recipient_email).to(eq("external@vendor.com"))
      end

      it "filters the gm_nudge fallback_chain payload identically — unverified contacts are not CC'd" do
        FlowEvent.record!(
          event_type: "escalation.fallback_fanout",
          tenant: tenant,
          subject: prompt,
          payload: {fallback_index: 0, fallback_email: "verified@smithtoyota.com"},
          occurred_at: Time.zone.parse("2026-06-07 10:00:00")
        )
        FlowEvent.record!(
          event_type: "escalation.fallback_fanout",
          tenant: tenant,
          subject: prompt,
          payload: {fallback_index: 1, fallback_email: "external@vendor.com"},
          occurred_at: Time.zone.parse("2026-06-11 10:00:00")
        )
        result = described_class.next_action_for(
          prompt: prompt,
          now: Time.zone.parse("2026-06-16 10:00:00")
        )
        expect(result.severity).to(eq(:gm_nudge))
        expect(result.payload[:fallback_chain]).to(
          eq(["verified@smithtoyota.com", "external@vendor.com"])
        )
      end
    end

    # FEAT-005 — per-tenant grace window overrides
    context("with per-tenant grace overrides") do
      it "respects tenant.escalation_due_soon_grace_days when set" do
        tenant.update!(escalation_due_soon_grace_days: 7)
        # 7 days before period_end (May 31) = May 24. With default 3 it would be May 28.
        # On May 24, the override should fire; default would not.
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-05-24 10:00:00"))
        expect(result&.severity).to(eq(:due_soon))
      end

      it "uses module default when tenant override is nil" do
        # Confirm default still applies (no override). On May 26 (5 days before period_end), default 3 should NOT yet fire.
        tenant.update!(escalation_due_soon_grace_days: nil)
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-05-26 10:00:00"))
        expect(result).to(be_nil)
      end

      it "respects tenant.escalation_overdue_grace_days when set" do
        # Set tenant grace to 1 day, with prior due_soon FlowEvent.
        tenant.update!(escalation_overdue_grace_days: 1)
        FlowEvent.record!(
          event_type: "escalation.due_soon",
          tenant: tenant,
          subject: prompt,
          payload: {},
          occurred_at: Time.zone.parse("2026-05-29 10:00:00")
        )
        # June 1 = period_end + 1 day
        result = described_class.next_action_for(prompt: prompt, now: Time.zone.parse("2026-06-01 10:00:00"))
        expect(result&.severity).to(eq(:overdue))
      end
    end
  end
end
