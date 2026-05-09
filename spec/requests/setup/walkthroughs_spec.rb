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

  let(:contact) do
    create(
      :contact,
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

      it "renders Step 1 — the assignment summary" do
        get(setup_walkthrough_path(signed_id: signed_id))
        expect(response.body).to(include("Smith Toyota"))
        expect(response.body).to(include("marketing strategy"))
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
end
