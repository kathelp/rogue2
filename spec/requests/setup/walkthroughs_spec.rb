require "rails_helper"

RSpec.describe "Setup::Walkthroughs", type: :request do
  let(:tenant) do
    create(
      :tenant,
      :confirmed,
      dealership_name: "Smith Toyota",
      gm_email: "jane@smithtoyota.com"
    )
  end

  # Verified by default — existing post-identity flow tests assume the contact
  # has already completed Step 1 of the walkthrough. Identity-step tests
  # (the "PATCH identity" / "GET identity branch" contexts below) override
  # this with an explicitly unverified contact.
  let(:contact) do
    create(
      :contact,
      :verified,
      tenant: tenant,
      email: "alex@smithtoyota.com",
      classification: "internal_staff"
    )
  end

  let(:question) do
    create(
      :tenant_question,
      tenant: tenant,
      key: "marketing_strategy",
      prompt: "Who controls your marketing strategy at Smith Toyota?"
    )
  end

  let!(:responsibility) do
    create(
      :responsibility,
      tenant: tenant,
      tenant_question: question,
      primary_contact: contact,
      gm_self_assigned: false
    )
  end

  let!(:source) do
    create(
      :source,
      tenant: tenant,
      domain: "marketing",
      responsibility_key: "marketing_strategy"
    )
  end

  let(:signed_id) { contact.invitee_setup_signed_id(expires_in: 7.days) }

  describe "GET /setup/:signed_id" do
    context("with a valid signed_id and unconfigured Source") do
      it "returns 200" do
        get(setup_walkthrough_path(signed_id: signed_id))
        expect(response).to(have_http_status(:ok))
      end

      it "renders Step 1 — the assignment summary using the question's deliverable, not the mangled prompt" do
        get(setup_walkthrough_path(signed_id: signed_id))
        expect(response.body).to(include("Smith Toyota"))
        expect(response.body).to(include("marketing strategy report"))
        expect(response.body).not_to(include("who controls"))
      end

      it "links to Step 2 — the method picker" do
        get(setup_walkthrough_path(signed_id: signed_id))
        expect(response.body).to(include("step=method"))
      end
    end

    context("with step=method and unconfigured Source") do
      it "renders the method picker form" do
        get(setup_walkthrough_path(signed_id: signed_id, step: "method"))
        expect(response).to(have_http_status(:ok))
        # Three radio options
        expect(response.body).to(include("value=\"form\""))
        expect(response.body).to(include("value=\"csv\""))
        expect(response.body).to(include("value=\"api_post\""))
      end
    end

    context("with a configured Source (resume)") do
      before do
        source.update!(
          submission_method: "form",
          configured_at: Time.current,
          configured_by_contact_id: contact.id
        )
      end

      it "always renders Step 3 (done) regardless of step param" do
        get(setup_walkthrough_path(signed_id: signed_id))
        expect(response.body).to(include("You're set up"))
      end

      it "shows the next due date" do
        # SubmissionPrompt seeded by the configuring action
        request_record = create(
          :request,
          tenant: tenant,
          source: source,
          metric_key: "strategy_summary",
          cadence: "monthly"
        )
        create(
          :submission_prompt,
          tenant: tenant,
          request: request_record,
          scheduled_for: Time.zone.parse("2026-06-01")
        )

        get(setup_walkthrough_path(signed_id: signed_id))
        expect(response.body).to(match(/2026|June|Jun/))
      end
    end

    context("with an invalid or expired signed_id") do
      it "renders an expired page with 404" do
        get(setup_walkthrough_path(signed_id: "not-a-real-token"))
        expect(response).to(have_http_status(:not_found))
        expect(response.body).to(include("expired"))
      end

      it "does not leak whether the contact exists" do
        # Make a real signed_id but for a non-existent purpose to force failure
        bogus = ActiveSupport::MessageVerifier.new("nope").generate(contact.id)
        get(setup_walkthrough_path(signed_id: bogus))
        expect(response).to(have_http_status(:not_found))
      end
    end
  end

  describe "PATCH /setup/:signed_id" do
    context("with submission_method=form") do
      it "returns 302 redirecting to step=done" do
        patch(
          setup_walkthrough_path(signed_id: signed_id),
          params: {source: {submission_method: "form"}}
        )
        expect(response).to(have_http_status(:found))
        expect(response.location).to(include("step=done"))
      end

      it "configures the Source" do
        patch(
          setup_walkthrough_path(signed_id: signed_id),
          params: {source: {submission_method: "form"}}
        )
        source.reload
        expect(source.submission_method).to(eq("form"))
        expect(source.configured_at).not_to(be_nil)
        expect(source.configured_by_contact_id).to(eq(contact.id))
      end

      it "creates Request rows for the catalog metrics of the question" do
        # Marketing catalog v1 — marketing_strategy has one metric: strategy_summary
        expect {
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: {source: {submission_method: "form"}}
          )
        }
          .to(change { Request.where(source: source).count }.by_at_least(1))
      end

      it "schedules at least one SubmissionPrompt" do
        expect {
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: {source: {submission_method: "form"}}
          )
        }
          .to(change { SubmissionPrompt.count }.by_at_least(1))
      end
    end

    context("with submission_method=csv (parked state — adapter generation in FEAT-002)") do
      it "still configures the Source with csv as method" do
        patch(
          setup_walkthrough_path(signed_id: signed_id),
          params: {source: {submission_method: "csv"}}
        )
        expect(source.reload.submission_method).to(eq("csv"))
      end
    end

    context("with an invalid submission_method") do
      it "re-renders the method picker with an error" do
        patch(
          setup_walkthrough_path(signed_id: signed_id),
          params: {source: {submission_method: "carrier_pigeon"}}
        )
        expect(response).to(have_http_status(:unprocessable_content))
        expect(source.reload.submission_method).to(be_nil)
      end
    end

    context("with an expired signed_id") do
      it "renders the expired page" do
        # generate the token NOW so travel_to ages it past expiry
        token = signed_id
        travel_to(8.days.from_now) do
          patch(
            setup_walkthrough_path(signed_id: token),
            params: {source: {submission_method: "form"}}
          )
          expect(response).to(have_http_status(:not_found))
        end
      end
    end
  end

  describe "Identity step (FEAT-006 FE pass)" do
    let(:contact) do
      create(
        :contact,
        tenant: tenant,
        email: "alex@smithtoyota.com",
        classification: "internal_staff"
      )
    end

    describe "GET /setup/:signed_id" do
      it "renders Step 1 of 4 — the identity form — when the contact is unverified" do
        get(setup_walkthrough_path(signed_id: signed_id))

        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("Step 1 of 4"))
        expect(response.body).to(include("Your details"))
        expect(response.body).to(include("First name"))
        expect(response.body).to(include("Last name"))
        expect(response.body).to(include("Mobile phone"))
        expect(response.body).to(include("Smith Toyota"))
      end

      it "renders identity even when ?step=method is requested for an unverified contact" do
        get(setup_walkthrough_path(signed_id: signed_id, step: "method"))

        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("Step 1 of 4"))
        expect(response.body).to(include("Your details"))
      end
    end

    describe "PATCH /setup/:signed_id with :contact params" do
      let(:valid_params) do
        {
          contact: {
            first_name: "Alex",
            last_name: "Rivera",
            phone: "(512) 555-1234"
          }
        }
      end

      context("with valid identity params") do
        it "redirects to step=summary" do
          patch(setup_walkthrough_path(signed_id: signed_id), params: valid_params)

          expect(response).to(have_http_status(:found))
          expect(response.location).to(include("step=summary"))
        end

        it "persists the three identity fields and marks the contact verified" do
          patch(setup_walkthrough_path(signed_id: signed_id), params: valid_params)
          contact.reload

          expect(contact.first_name).to(eq("Alex"))
          expect(contact.last_name).to(eq("Rivera"))
          expect(contact.phone).to(eq("+15125551234"))
          expect(contact.verified?).to(be(true))
        end

        it "records a contact.verified FlowEvent atomically with the update" do
          expect { patch(setup_walkthrough_path(signed_id: signed_id), params: valid_params) }
            .to(change { FlowEvent.where(event_type: "contact.verified").count }.by(1))
        end
      end

      context("with a blank first_name") do
        it "re-renders identity with 422 and a field-specific error" do
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: valid_params.deep_merge(contact: {first_name: ""})
          )

          expect(response).to(have_http_status(:unprocessable_content))
          expect(response.body).to(include("id=\"first-name-error\""))
          expect(response.body).to(match(/First name.{0,20}blank/))
        end

        it "does not update the contact or write a FlowEvent" do
          expect {
            patch(
              setup_walkthrough_path(signed_id: signed_id),
              params: valid_params.deep_merge(contact: {first_name: ""})
            )
          }
            .not_to(change { FlowEvent.where(event_type: "contact.verified").count })
          expect(contact.reload.verified?).to(be(false))
        end
      end

      context("with a blank last_name") do
        it "re-renders identity with 422 and a field-specific error" do
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: valid_params.deep_merge(contact: {last_name: ""})
          )

          expect(response).to(have_http_status(:unprocessable_content))
          expect(response.body).to(include("id=\"last-name-error\""))
          expect(response.body).to(match(/Last name.{0,20}blank/))
        end
      end

      context("with a blank phone") do
        it "re-renders identity with 422 and a blank-phone error" do
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: valid_params.deep_merge(contact: {phone: ""})
          )

          expect(response).to(have_http_status(:unprocessable_content))
          expect(response.body).to(include("id=\"phone-error\""))
          expect(response.body).to(match(/Mobile phone.{0,20}blank/))
        end
      end

      context("with an unparseable phone") do
        it "re-renders identity with 422 and the invalid-format error" do
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: valid_params.deep_merge(contact: {phone: "phone-please"})
          )

          expect(response).to(have_http_status(:unprocessable_content))
          expect(response.body).to(include("valid US mobile number"))
        end
      end

      context("on validation failure") do
        it "preserves submitted first_name and last_name in the re-rendered form" do
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: valid_params.deep_merge(contact: {phone: ""})
          )

          expect(response.body).to(include("value=\"Alex\""))
          expect(response.body).to(include("value=\"Rivera\""))
        end

        it "preserves the raw submitted phone via @phone_attempt (not the encrypted column)" do
          patch(
            setup_walkthrough_path(signed_id: signed_id),
            params: valid_params.deep_merge(contact: {first_name: ""})
          )

          expect(response.body).to(include("(512) 555-1234"))
        end
      end

      context("with an expired signed_id on the identity branch") do
        it "renders the expired page with 404 (regression guard)" do
          token = signed_id
          travel_to(8.days.from_now) do
            patch(
              setup_walkthrough_path(signed_id: token),
              params: valid_params
            )
            expect(response).to(have_http_status(:not_found))
          end
        end
      end
    end

    describe "GET /setup/:signed_id after a contact has verified" do
      before do
        contact.update!(first_name: "Alex", last_name: "Rivera", phone: "+15125551234")
      end

      it "skips the identity step and renders Step 2 — summary" do
        get(setup_walkthrough_path(signed_id: signed_id))

        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("Step 2 of 4"))
        expect(response.body).to(include("Your assignment"))
      end
    end
  end

  describe "Step-counter regressions in existing views" do
    it "summary renders Step 2 of 4 (was 1 of 3)" do
      get(setup_walkthrough_path(signed_id: signed_id))

      expect(response.body).to(include("Step 2 of 4"))
      expect(response.body).not_to(include("Step 1 of 3"))
    end

    it "method_picker renders Step 3 of 4 (was 2 of 3)" do
      get(setup_walkthrough_path(signed_id: signed_id, step: "method"))

      expect(response.body).to(include("Step 3 of 4"))
      expect(response.body).not_to(include("Step 2 of 3"))
    end

    it "done greets the contact by first_name when verified" do
      source.update!(
        submission_method: "form",
        configured_at: Time.current,
        configured_by_contact_id: contact.id
      )

      get(setup_walkthrough_path(signed_id: signed_id))

      expect(response.body).to(match(/You're set up, #{contact.first_name}\./))
    end

    it "done renders the next-prompt sentence using the question's deliverable, not the mangled prompt" do
      source.update!(
        submission_method: "form",
        configured_at: Time.current,
        configured_by_contact_id: contact.id
      )
      request_record = create(
        :request,
        tenant: tenant,
        source: source,
        metric_key: "strategy_summary",
        cadence: "monthly"
      )
      create(
        :submission_prompt,
        tenant: tenant,
        request: request_record,
        scheduled_for: Time.zone.parse("2026-06-01")
      )

      get(setup_walkthrough_path(signed_id: signed_id))

      expect(response.body).to(include("marketing strategy report"))
      expect(response.body).not_to(include("who controls"))
    end

    context("when the contact is verified but has no active responsibility") do
      let!(:responsibility) { nil }

      it "shows the 'details are saved' acknowledgment and suppresses the Continue link" do
        get(setup_walkthrough_path(signed_id: signed_id))

        expect(response.body).to(include("Your details are saved"))
        expect(response.body).not_to(match(/<a[^>]*>\s*Continue\s*<\/a>/m))
      end
    end
  end
end
