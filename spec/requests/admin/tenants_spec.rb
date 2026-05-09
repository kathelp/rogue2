require "rails_helper"

RSpec.describe "Admin::Tenants", type: :request do
  let(:valid_headers) do
    credentials = Base64.strict_encode64("admin:admin-test-password")
    {"Authorization" => "Basic #{credentials}"}
  end

  let(:invalid_headers) do
    credentials = Base64.strict_encode64("wrong:credentials")
    {"Authorization" => "Basic #{credentials}"}
  end

  describe "GET /admin/tenants/new" do
    context("without basic auth") do
      it "returns 401" do
        get(new_admin_tenant_path)
        expect(response).to(have_http_status(:unauthorized))
      end
    end

    context("with valid basic auth") do
      it "returns 200 and renders the form" do
        get(new_admin_tenant_path, headers: valid_headers)
        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("Seed tenant"))
      end
    end

    context("with invalid basic auth") do
      it "returns 401" do
        get(new_admin_tenant_path, headers: invalid_headers)
        expect(response).to(have_http_status(:unauthorized))
      end
    end
  end

  describe "POST /admin/tenants" do
    let(:valid_params) do
      {
        tenant: {
          dealership_name: "Smith Toyota",
          gm_name: "Jane Smith",
          gm_email: "jane@smithtoyota.com"
        }
      }
    end

    context("without basic auth") do
      it "returns 401" do
        post(admin_tenants_path, params: valid_params)
        expect(response).to(have_http_status(:unauthorized))
      end
    end

    context("with valid auth and valid params") do
      it "creates a Tenant and redirects to show" do
        expect {
          post(admin_tenants_path, params: valid_params, headers: valid_headers)
        }
          .to(change(Tenant, :count).by(1))

        tenant = Tenant.last
        expect(response).to(redirect_to(admin_tenant_path(tenant)))
      end

      it "sets the flash notice with the dealership name and email" do
        post(admin_tenants_path, params: valid_params, headers: valid_headers)
        expect(flash[:notice]).to(include("Smith Toyota"))
        expect(flash[:notice]).to(include("jane@smithtoyota.com"))
      end

      it "enqueues a confirmation email" do
        expect {
          post(admin_tenants_path, params: valid_params, headers: valid_headers)
        }
          .to(have_enqueued_mail(OnboardingMailer, :confirmation_email))
      end
    end

    context("with valid auth and invalid params (missing dealership_name)") do
      let(:invalid_params) do
        {tenant: {dealership_name: "", gm_name: "Jane Smith", gm_email: "jane@smithtoyota.com"}}
      end

      it "does not create a Tenant" do
        expect {
          post(admin_tenants_path, params: invalid_params, headers: valid_headers)
        }
          .not_to(change(Tenant, :count))
      end

      it "re-renders the new form with unprocessable_entity status" do
        post(admin_tenants_path, params: invalid_params, headers: valid_headers)
        expect(response).to(have_http_status(:unprocessable_content))
        expect(response.body).to(include("Seed tenant"))
      end
    end
  end

  describe "GET /admin/tenants/:id" do
    let(:tenant) { create(:tenant) }

    context("without basic auth") do
      it "returns 401" do
        get(admin_tenant_path(tenant))
        expect(response).to(have_http_status(:unauthorized))
      end
    end

    context("with valid auth") do
      it "returns 200 and shows tenant info" do
        get(admin_tenant_path(tenant), headers: valid_headers)
        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include(tenant.dealership_name))
        expect(response.body).to(include(tenant.gm_name))
      end
    end
  end

  describe "POST /admin/tenants/:id/resend_confirmation" do
    let(:tenant) { create(:tenant) }

    context("when tenant is pending_confirm") do
      it "re-queues the confirmation email" do
        expect {
          post(resend_confirmation_admin_tenant_path(tenant), headers: valid_headers)
        }
          .to(have_enqueued_mail(OnboardingMailer, :confirmation_email))
      end

      it "updates confirmation_sent_at" do
        freeze_time do
          post(resend_confirmation_admin_tenant_path(tenant), headers: valid_headers)
          expect(tenant.reload.confirmation_sent_at).to(be_within(1.second).of(Time.current))
        end
      end

      it "redirects to show with notice" do
        post(resend_confirmation_admin_tenant_path(tenant), headers: valid_headers)
        expect(response).to(redirect_to(admin_tenant_path(tenant)))
        expect(flash[:notice]).to(include("re-queued"))
      end
    end

    context("when tenant is already confirmed") do
      let(:tenant) { create(:tenant, :confirmed) }

      it "does not enqueue any mail" do
        expect {
          post(resend_confirmation_admin_tenant_path(tenant), headers: valid_headers)
        }
          .not_to(have_enqueued_mail)
      end

      it "redirects with an alert" do
        post(resend_confirmation_admin_tenant_path(tenant), headers: valid_headers)
        expect(response).to(redirect_to(admin_tenant_path(tenant)))
        expect(flash[:alert]).to(include("already confirmed"))
      end
    end
  end
end
