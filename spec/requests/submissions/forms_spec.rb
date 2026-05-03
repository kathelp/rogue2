require "rails_helper"

RSpec.describe "Submissions::Forms", type: :request do
  let(:tenant) { create(:tenant, :confirmed, dealership_name: "Smith Toyota") }
  let(:contact) { create(:contact, tenant: tenant, email: "alex@smithtoyota.com") }
  let(:source) do
    create(:source, :configured, tenant: tenant,
           responsibility_key: "marketing_strategy",
           configured_by_contact: contact)
  end
  let(:request_record) do
    create(:request, tenant: tenant, source: source,
           metric_key: "strategy_summary", cadence: "monthly")
  end
  let(:prompt) do
    create(:submission_prompt, tenant: tenant, request: request_record,
           status: "sent", scheduled_for: Time.zone.parse("2026-05-01 10:00:00"))
  end
  let(:signed_id) { prompt.submission_form_signed_id(expires_in: 14.days) }

  describe "GET /submissions/:signed_id" do
    context "with a valid token and prompt :sent" do
      it "returns 200 and renders the form" do
        get submission_form_path(signed_id: signed_id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Smith Toyota")
        expect(response.body).to include("strategy summary")
        expect(response.body).to include('name="submission[value]"')
        expect(response.body).to include('name="submission[notes]"')
      end
    end

    context "with a fulfilled prompt (idempotent rebound)" do
      before { prompt.update!(status: :fulfilled, fulfilled_at: 1.hour.ago) }

      it "renders the already-submitted page (no form)" do
        get submission_form_path(signed_id: signed_id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/already submitted/i)
        expect(response.body).not_to include('name="submission[value]"')
      end
    end

    context "with an expired token" do
      it "returns 404 with the expired view" do
        token = signed_id
        travel_to(15.days.from_now) do
          get submission_form_path(signed_id: token)
          expect(response).to have_http_status(:not_found)
          expect(response.body).to match(/expired/i)
        end
      end
    end

    context "with an invalid token" do
      it "returns 404 with the expired view" do
        get submission_form_path(signed_id: "totally-bogus-token")
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /submissions/:signed_id" do
    context "with valid params" do
      it "creates a Submission row" do
        expect {
          post submission_form_path(signed_id: signed_id),
               params: { submission: { value: "42500.5", notes: "May numbers" } }
        }.to change(Submission, :count).by(1)
      end

      it "marks the prompt :fulfilled" do
        post submission_form_path(signed_id: signed_id),
             params: { submission: { value: "42500" } }
        expect(prompt.reload.status).to eq("fulfilled")
      end

      it "renders a thank-you page on the redirect target" do
        post submission_form_path(signed_id: signed_id),
             params: { submission: { value: "42500" } }
        expect(response).to have_http_status(:found)
        follow_redirect!
        expect(response.body).to match(/got it|thanks|received/i)
      end

      it "records a submission.captured FlowEvent" do
        expect {
          post submission_form_path(signed_id: signed_id),
               params: { submission: { value: "42500" } }
        }.to change { FlowEvent.where(event_type: "submission.captured").count }.by(1)
      end
    end

    context "with invalid value" do
      it "returns 422 and re-renders the form" do
        post submission_form_path(signed_id: signed_id),
             params: { submission: { value: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('name="submission[value]"')
      end

      it "does not create a Submission" do
        expect {
          post submission_form_path(signed_id: signed_id),
               params: { submission: { value: "abc" } }
        }.not_to change(Submission, :count)
      end
    end

    context "with an already-fulfilled prompt (idempotent re-POST)" do
      before do
        post submission_form_path(signed_id: signed_id),
             params: { submission: { value: "1000" } }
      end

      it "does not create a second Submission" do
        expect {
          post submission_form_path(signed_id: signed_id),
               params: { submission: { value: "9999" } }
        }.not_to change(Submission, :count)
      end
    end
  end
end
