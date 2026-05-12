require "rails_helper"

# End-to-end integration test of the TASK-001 + TASK-002 + TASK-004
# happy path: admin seeds Tenant → GM clicks confirm → question email
# arrives → GM replies with a CC → ack + invitee setup email arrive →
# invitee completes walkthrough → SubmissionPrompt scheduled → sender
# job delivers it → invitee clicks submit link → captures Submission.
#
# This is the integration gate the TASK-001 plan named but didn't ship.
# Added in TASK-005 reflection cleanup.
RSpec.describe "GM email-first onboarding full loop", type: :system do
  include(ActiveJob::TestHelper)
  include(ActionMailbox::TestHelper)

  before { driven_by(:rack_test) }

  def admin_basic_auth
    page.driver.browser.basic_authorize("admin", "admin-test-password")
  end

  def link_in(mail, pattern)
    body = mail.html_part&.body&.decoded || mail.body.decoded
    body[/(?:href="|<)([^"<>\s]*#{Regexp.escape(pattern)}[^"<>\s]*)/, 1]
  end

  it "walks the full email-first onboarding loop end to end" do
    # ─────────────────────────────────────────────────────────────────
    # 1. Rogue staff seeds a Tenant via /admin/tenants/new
    # ─────────────────────────────────────────────────────────────────
    admin_basic_auth
    visit(new_admin_tenant_path)
    fill_in("Dealership name", with: "Smith Toyota")
    fill_in("GM name", with: "Jane Smith")
    fill_in("GM email", with: "jane@smithtoyota.com")

    expect {
      perform_enqueued_jobs { click_button("Seed tenant") }
    }
      .to(change(ActionMailer::Base.deliveries, :count).by(1))

    tenant = Tenant.find_by(gm_email_normalized: "jane@smithtoyota.com")
    expect(tenant.status).to(eq("pending_confirm"))

    confirmation_mail = ActionMailer::Base.deliveries.last
    expect(confirmation_mail.to).to(eq(["jane@smithtoyota.com"]))
    expect(confirmation_mail.subject).to(include("Welcome to Rogue"))

    # ─────────────────────────────────────────────────────────────────
    # 2. GM clicks the confirmation link in the email
    # ─────────────────────────────────────────────────────────────────
    confirm_url = link_in(confirmation_mail, "/onboarding/confirmations/")
    expect(confirm_url).to(be_present)

    confirm_path = URI.parse(confirm_url).path
    perform_enqueued_jobs { visit(confirm_path) }

    expect(page).to(have_text("You're confirmed"))
    expect(tenant.reload.status).to(eq("confirmed"))

    # First question email is queued via EnqueueFirstQuestionJob.
    # The job enqueues a deliver_later with wait_until — drain it inline:
    perform_enqueued_jobs

    question_mail = ActionMailer::Base.deliveries.find { |m|
      m.subject&.include?("[Smith Toyota Onboarding]")
    }
    expect(question_mail).not_to(be_nil)
    expect(question_mail.to).to(eq(["jane@smithtoyota.com"]))

    # First marketing-catalog question is "marketing_strategy"
    first_question = tenant
      .tenant_questions
      .where(status: "sent")
      .order(:position)
      .first
    expect(first_question.key).to(eq("marketing_strategy"))

    # ─────────────────────────────────────────────────────────────────
    # 3. GM replies with Alex on CC (assigning marketing_strategy to Alex)
    # ─────────────────────────────────────────────────────────────────
    onboarding_address = "onboarding+#{tenant.onboarding_token}@inbound.rogue.example"

    perform_enqueued_jobs do
      receive_inbound_email_from_mail(
        to: onboarding_address,
        from: "jane@smithtoyota.com",
        cc: "alex@smithtoyota.com",
        subject: "Re: [Smith Toyota Onboarding] Who controls your marketing strategy at Smith Toyota?",
        body: "That's Alex, our CMO.",
        in_reply_to: "<#{first_question.outbound_message_id}>"
      )
    end

    # Responsibility + Source created
    responsibility = Responsibility.where(tenant_question: first_question, status: :active).first
    expect(responsibility).not_to(be_nil)
    expect(responsibility.primary_contact.email_normalized).to(eq("alex@smithtoyota.com"))

    source = tenant.sources.find_by(domain: "marketing", responsibility_key: "marketing_strategy")
    expect(source).not_to(be_nil)

    # Two outbound mails should have been queued: in_thread_ack to Jane + invitee_setup_email to Alex
    setup_mail = ActionMailer::Base.deliveries.find { |m|
      m.to.include?("alex@smithtoyota.com") && m.subject&.include?("set up your details")
    }
    expect(setup_mail).not_to(be_nil)

    # ─────────────────────────────────────────────────────────────────
    # 4. Alex clicks the setup link and completes the walkthrough
    # ─────────────────────────────────────────────────────────────────
    setup_url = link_in(setup_mail, "/setup/")
    expect(setup_url).to(be_present)

    setup_path = URI.parse(setup_url).path

    visit(setup_path)

    # Step 1 of 4: identity step (FEAT-006 — unverified contact must self-verify)
    expect(page).to(have_text("Step 1 of 4"))
    expect(page).to(have_text("Smith Toyota"))
    fill_in("First name", with: "Alex")
    fill_in("Last name", with: "Rivera")
    fill_in("Mobile phone", with: "(512) 555-1234")
    click_button("Continue")

    # Step 2 of 4: assignment summary
    expect(page).to(have_text("Step 2 of 4"))
    expect(page).to(have_text("Smith Toyota"))
    click_link("Continue")

    # Step 3 of 4: method picker
    expect(page).to(have_field("source_submission_method_form"))
    choose("source_submission_method_form")
    perform_enqueued_jobs { click_button("Finish setup") }

    # Step 4 of 4: thank-you (submission method captured)
    expect(page).to(have_text(/set up|got it|received/i))

    # Source is now configured, Request + SubmissionPrompt provisioned
    expect(source.reload.submission_method).to(eq("form"))
    request_record = source.requests.first
    expect(request_record).not_to(be_nil)
    expect(request_record.metric_key).to(eq("strategy_summary"))

    initial_prompt = SubmissionPrompt.where(request: request_record).first
    expect(initial_prompt).not_to(be_nil)
    expect(initial_prompt.status).to(eq("pending"))

    # ─────────────────────────────────────────────────────────────────
    # 5. Time advances; sender job picks up the due prompt; Alex submits
    # ─────────────────────────────────────────────────────────────────
    travel_to(initial_prompt.scheduled_for + 1.hour) do
      perform_enqueued_jobs { SubmissionPromptSenderJob.perform_now }
    end

    expect(initial_prompt.reload.status).to(eq("sent"))

    prompt_mail = ActionMailer::Base.deliveries.find { |m|
      m.to.include?("alex@smithtoyota.com") && m.subject&.match?(/strategy summary/i)
    }
    expect(prompt_mail).not_to(be_nil)

    submit_url = link_in(prompt_mail, "/submissions/")
    expect(submit_url).to(be_present)

    submit_path = URI.parse(submit_url).path
    visit(submit_path)
    fill_in("field-value", with: "42500")
    fill_in("field-notes", with: "Strong May numbers")
    perform_enqueued_jobs { click_button("Submit") }

    expect(page).to(have_text(/got it|received/i))

    submission = Submission.where(submission_prompt: initial_prompt).first
    expect(submission).not_to(be_nil)
    expect(submission.value.to_f).to(eq(42_500.0))
    expect(initial_prompt.reload.status).to(eq("fulfilled"))

    # ─────────────────────────────────────────────────────────────────
    # Final assertion: the audit trail is intact end-to-end
    # ─────────────────────────────────────────────────────────────────
    flow_event_types = FlowEvent.where(tenant: tenant).pluck(:event_type)
    expect(flow_event_types).to(
      include(
        "tenant.confirmed",
        "question.sent",
        "reply.parsed",
        "responsibility.created",
        "source.configured",
        "submission.prompt_sent",
        "submission.captured"
      )
    )
  end
end
