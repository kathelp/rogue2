require "rails_helper"

RSpec.describe "Dashboards", type: :request do
  let(:tenant) { create(:tenant, :active, dealership_name: "Smith Toyota") }
  let(:signed_id) { tenant.dashboard_signed_id(expires_in: 8.days) }

  describe "GET /dashboard/:signed_id" do
    context("with a valid signed_id") do
      it "returns 200" do
        get(dashboard_path(signed_id: signed_id))
        expect(response).to(have_http_status(:ok))
      end

      it "renders a read-only summary mentioning the dealership name" do
        get(dashboard_path(signed_id: signed_id))
        expect(response.body).to(include("Smith Toyota"))
      end

      it "lists each active responsibility" do
        question = create(
          :tenant_question,
          tenant: tenant,
          key: "marketing_strategy",
          prompt: "Who controls your marketing strategy?"
        )
        contact = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
        create(
          :responsibility,
          tenant: tenant,
          tenant_question: question,
          primary_contact: contact
        )

        get(dashboard_path(signed_id: signed_id))
        expect(response.body).to(include("alex@smithtoyota.com"))
      end

      # FEAT-005 — status badges
      it "renders the per-row status as an inline-colored badge span" do
        question = create(
          :tenant_question,
          tenant: tenant,
          key: "marketing_strategy",
          prompt: "Who controls your marketing strategy?"
        )
        contact = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
        create(
          :responsibility,
          tenant: tenant,
          tenant_question: question,
          primary_contact: contact
        )

        get(dashboard_path(signed_id: signed_id))
        expect(response.body).to(match(/<span[^>]*background:\s*#[0-9a-f]+/i))
      end
    end

    context("with an invalid signed_id") do
      it "renders the expired page with 404" do
        get(dashboard_path(signed_id: "totally-bogus-token"))
        expect(response).to(have_http_status(:not_found))
        expect(response.body).to(include("expired"))
      end
    end

    context("with an expired signed_id") do
      it "renders the expired page" do
        # generate now
        token = signed_id
        travel_to(9.days.from_now) do
          get(dashboard_path(signed_id: token))
          expect(response).to(have_http_status(:not_found))
        end
      end
    end
  end
end
