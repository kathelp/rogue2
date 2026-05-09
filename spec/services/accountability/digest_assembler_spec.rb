require "rails_helper"

RSpec.describe Accountability::DigestAssembler do
  let(:tenant) { create(:tenant, :active) }

  describe ".call" do
    it "returns an empty rows array and empty: true when the tenant has no responsibilities" do
      digest = described_class.call(tenant: tenant)
      expect(digest.rows).to(eq([]))
      expect(digest).to(be_empty)
    end

    it "returns one row per active responsibility" do
      q1 = create(
        :tenant_question,
        tenant: tenant,
        key: "marketing_strategy",
        prompt: "Who controls your marketing strategy?"
      )
      q2 = create(
        :tenant_question,
        tenant: tenant,
        key: "dealer_website",
        prompt: "Who manages your dealer website?"
      )
      c1 = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      c2 = create(:contact, tenant: tenant, email: "taylor@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q1, primary_contact: c1)
      create(:responsibility, tenant: tenant, tenant_question: q2, primary_contact: c2)

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.length).to(eq(2))
      expect(digest).not_to(be_empty)
    end

    it "marks pending_setup when the source is not yet configured" do
      q = create(
        :tenant_question,
        tenant: tenant,
        key: "marketing_strategy",
        prompt: "Who controls your marketing strategy?"
      )
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q, primary_contact: c)
      create(:source, tenant: tenant, domain: "marketing", responsibility_key: "marketing_strategy")

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.first.status).to(eq(:pending_setup))
    end

    it "marks pending_first_submission when configured but no submissions yet" do
      q = create(
        :tenant_question,
        tenant: tenant,
        key: "marketing_strategy",
        prompt: "Who controls your marketing strategy?"
      )
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q, primary_contact: c)
      source = create(
        :source,
        :configured,
        tenant: tenant,
        domain: "marketing",
        responsibility_key: "marketing_strategy",
        configured_by_contact: c
      )
      create(
        :request,
        tenant: tenant,
        source: source,
        metric_key: "strategy_summary",
        cadence: "monthly"
      )

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.first.status).to(eq(:pending_first_submission))
    end

    it "marks on_time when at least one Submission exists for the current period" do
      q = create(
        :tenant_question,
        tenant: tenant,
        key: "marketing_strategy",
        prompt: "Who controls your marketing strategy?"
      )
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q, primary_contact: c)
      source = create(
        :source,
        :configured,
        tenant: tenant,
        domain: "marketing",
        responsibility_key: "marketing_strategy",
        configured_by_contact: c
      )
      request_record = create(
        :request,
        tenant: tenant,
        source: source,
        metric_key: "strategy_summary",
        cadence: "monthly"
      )
      period_start = Time.current.in_time_zone(tenant.time_zone).beginning_of_month.to_date
      prompt = create(
        :submission_prompt,
        tenant: tenant,
        request: request_record,
        status: "fulfilled",
        scheduled_for: Time.current,
        fulfilled_at: Time.current
      )
      create(
        :submission,
        tenant: tenant,
        request: request_record,
        submission_prompt: prompt,
        submitted_by_contact: c,
        period_starting: period_start
      )

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.first.status).to(eq(:on_time))
    end

    it "marks late when prompt is sent, period passed, no submission, no escalation FlowEvents yet" do
      q = create(
        :tenant_question,
        tenant: tenant,
        key: "marketing_strategy",
        prompt: "Who controls your marketing strategy?"
      )
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q, primary_contact: c)
      source = create(
        :source,
        :configured,
        tenant: tenant,
        domain: "marketing",
        responsibility_key: "marketing_strategy",
        configured_by_contact: c
      )
      request_record = create(
        :request,
        tenant: tenant,
        source: source,
        metric_key: "strategy_summary",
        cadence: "monthly"
      )
      # Prompt scheduled for last month, period has passed, no submission yet.
      last_month_start = Time.current.in_time_zone(tenant.time_zone).beginning_of_month - 1.month
      create(
        :submission_prompt,
        tenant: tenant,
        request: request_record,
        status: "sent",
        scheduled_for: last_month_start,
        sent_at: last_month_start
      )

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.first.status).to(eq(:late))
    end

    it "marks overdue once a fallback_fanout or gm_nudge FlowEvent exists" do
      q = create(
        :tenant_question,
        tenant: tenant,
        key: "marketing_strategy",
        prompt: "Who controls your marketing strategy?"
      )
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, tenant: tenant, tenant_question: q, primary_contact: c)
      source = create(
        :source,
        :configured,
        tenant: tenant,
        domain: "marketing",
        responsibility_key: "marketing_strategy",
        configured_by_contact: c
      )
      request_record = create(
        :request,
        tenant: tenant,
        source: source,
        metric_key: "strategy_summary",
        cadence: "monthly"
      )
      last_month_start = Time.current.in_time_zone(tenant.time_zone).beginning_of_month - 1.month
      prompt = create(
        :submission_prompt,
        tenant: tenant,
        request: request_record,
        status: "sent",
        scheduled_for: last_month_start,
        sent_at: last_month_start
      )
      FlowEvent.record!(
        event_type: "escalation.fallback_fanout",
        tenant: tenant,
        subject: prompt,
        payload: {}
      )

      digest = described_class.call(tenant: tenant)
      expect(digest.rows.first.status).to(eq(:overdue))
    end

    it "ignores superseded responsibilities" do
      q = create(
        :tenant_question,
        tenant: tenant,
        key: "marketing_strategy",
        prompt: "Who controls your marketing strategy?"
      )
      c = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
      create(:responsibility, :superseded, tenant: tenant, tenant_question: q, primary_contact: c)

      digest = described_class.call(tenant: tenant)
      expect(digest.rows).to(eq([]))
    end
  end
end
