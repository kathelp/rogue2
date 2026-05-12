require "rails_helper"

# AC-INTEGRATION-1 (TASK-009 / FEAT-006 FE pass).
#
# Round-trip: when a CC'd contact lands in the system unverified and then
# completes the identity step at /setup/:signed_id, the escalation cascade's
# verification gate (TASK-008 / FEAT-006 backend) lifts on the very next
# evaluation. Pre-identity = filtered out of fallback chains; post-identity
# = included. One spec exercises the full pipeline from
# OnboardingMailbox#handle_assignment through the Capybara-driven identity
# form to the cascade's `fallback_emails_for` decision.
RSpec.describe "Contact self-verification un-gates the escalation cascade", type: :system do
  include(ActionMailbox::TestHelper)
  include(ActiveJob::TestHelper)

  before { driven_by(:rack_test) }

  it "lifts the cascade's verification gate once the cc'd contact completes identity" do
    # ─────────────────────────────────────────────────────────────────
    # Setup: confirmed tenant, marketing_strategy question already sent
    # ─────────────────────────────────────────────────────────────────
    tenant = create(
      :tenant,
      :confirmed,
      dealership_name: "Smith Toyota",
      gm_email: "jane@smithtoyota.com",
      onboarding_token: "fb12345abcdef"
    )
    create(
      :tenant_question,
      :sent,
      tenant: tenant,
      key: "marketing_strategy",
      prompt: "Who controls your marketing strategy at Smith Toyota?",
      outbound_message_id: "onb-q-marketing-strategy@inbound.rogue.example"
    )

    # ─────────────────────────────────────────────────────────────────
    # 1. GM reply CCs new contact Alex (mailbox promotes him via
    #    OnboardingMailbox#handle_assignment, creating his Contact +
    #    Responsibility + Source for marketing_strategy)
    # ─────────────────────────────────────────────────────────────────
    onboarding_address = "onboarding+#{tenant.onboarding_token}@inbound.rogue.example"

    perform_enqueued_jobs do
      receive_inbound_email_from_mail(
        to: onboarding_address,
        from: "jane@smithtoyota.com",
        cc: "alex@smithtoyota.com",
        subject: "Re: [Smith Toyota Onboarding] Who controls your marketing strategy at Smith Toyota?",
        body: "That's Alex, our CMO.",
        in_reply_to: "<onb-q-marketing-strategy@inbound.rogue.example>"
      )
    end

    alex = Contact.find_by(email_normalized: "alex@smithtoyota.com")
    expect(alex).not_to(be_nil)
    expect(alex.unverified?).to(be(true))

    # ─────────────────────────────────────────────────────────────────
    # 2. A parallel marketing_budget responsibility names Alex as a
    #    fallback. (Built directly here — exercising the GM-reply path
    #    twice would obscure the gating round-trip, which is the spec's
    #    point. The mailbox path is already covered upstream.)
    # ─────────────────────────────────────────────────────────────────
    budget_question = create(
      :tenant_question,
      :sent,
      tenant: tenant,
      key: "marketing_budget",
      prompt: "Who owns your marketing budget at Smith Toyota?"
    )
    budget_primary = create(:contact, :verified, tenant: tenant, email: "diana@smithtoyota.com")
    create(
      :responsibility,
      tenant: tenant,
      tenant_question: budget_question,
      primary_contact: budget_primary,
      fallback_contact_emails: ["alex@smithtoyota.com"]
    )
    budget_source = create(
      :source,
      tenant: tenant,
      domain: "marketing",
      responsibility_key: "marketing_budget"
    )
    budget_request = create(
      :request,
      tenant: tenant,
      source: budget_source,
      metric_key: "budget_summary",
      cadence: "monthly"
    )
    budget_prompt = create(
      :submission_prompt,
      tenant: tenant,
      request: budget_request,
      scheduled_for: 1.month.ago
    )

    # ─────────────────────────────────────────────────────────────────
    # 3. Pre-verification: cascade filters Alex out of the fallback list
    # ─────────────────────────────────────────────────────────────────
    fallbacks_pre = OnboardingFlow::EscalationCascade.send(:fallback_emails_for, budget_prompt)
    expect(fallbacks_pre).not_to(include("alex@smithtoyota.com"))

    # ─────────────────────────────────────────────────────────────────
    # 4. Alex receives + clicks the setup link; identity step lands
    #    him on Step 1 of 4
    # ─────────────────────────────────────────────────────────────────
    setup_mail = ActionMailer::Base.deliveries.find { |m|
      m.to.include?("alex@smithtoyota.com") && m.subject&.include?("set up your details")
    }
    expect(setup_mail).not_to(be_nil)

    setup_url = setup_mail.html_part.body.decoded[/href="([^"]*\/setup\/[^"]+)"/, 1]
    expect(setup_url).to(be_present)
    setup_path = URI.parse(setup_url).path

    visit(setup_path)

    expect(page).to(have_text("Step 1 of 4"))
    fill_in("First name", with: "Alex")
    fill_in("Last name", with: "Rivera")
    fill_in("Mobile phone", with: "(512) 555-1234")
    click_button("Continue")

    expect(page).to(have_text("Step 2 of 4"))
    alex.reload
    expect(alex.verified?).to(be(true))

    # ─────────────────────────────────────────────────────────────────
    # 5. Post-verification: same cascade call now INCLUDES Alex.
    #    Same prompt, same responsibility — only Alex's Contact state
    #    changed. The gate flipped.
    # ─────────────────────────────────────────────────────────────────
    fallbacks_post = OnboardingFlow::EscalationCascade.send(:fallback_emails_for, budget_prompt)
    expect(fallbacks_post).to(include("alex@smithtoyota.com"))

    # ─────────────────────────────────────────────────────────────────
    # 6. FlowEvent audit trail captured the verification
    # ─────────────────────────────────────────────────────────────────
    verified_event = FlowEvent
      .where(
        event_type: "contact.verified",
        subject_type: "Contact",
        subject_id: alex.id
      )
      .first
    expect(verified_event).not_to(be_nil)
  end
end
