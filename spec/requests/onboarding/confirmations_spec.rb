require "rails_helper"

RSpec.describe "Onboarding::Confirmations", type: :request do
  include(ActiveJob::TestHelper)

  describe "GET /onboarding/confirmations/:signed_id" do
    context("with a valid signed_id for a pending_confirm tenant") do
      let(:tenant) { create(:tenant) }
      let(:signed_id) { tenant.gm_confirm_signed_id(expires_in: 72.hours) }

      it "confirms the tenant" do
        get(onboarding_confirmation_path(signed_id: signed_id))
        expect(tenant.reload.status).to(eq("confirmed"))
      end

      it "sets confirmed_at" do
        freeze_time do
          get(onboarding_confirmation_path(signed_id: signed_id))
          expect(tenant.reload.confirmed_at).to(be_within(1.second).of(Time.current))
        end
      end

      it "records a tenant.confirmed FlowEvent" do
        expect {
          get(onboarding_confirmation_path(signed_id: signed_id))
        }
          .to(change(FlowEvent, :count).by(1))

        expect(FlowEvent.last.event_type).to(eq("tenant.confirmed"))
      end

      it "renders the show page with confirmation message" do
        get(onboarding_confirmation_path(signed_id: signed_id))
        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("You're confirmed."))
      end

      it "enqueues EnqueueFirstQuestionJob" do
        expect {
          get(onboarding_confirmation_path(signed_id: signed_id))
        }
          .to(
            have_enqueued_job(OnboardingFlow::EnqueueFirstQuestionJob)
              .with(tenant_id: tenant.id)
          )
      end
    end

    context("with an invalid/expired signed_id") do
      it "renders the invalid page with not_found status" do
        get(onboarding_confirmation_path(signed_id: "invalid-token-xyz"))
        expect(response).to(have_http_status(:not_found))
        expect(response.body).to(include("no longer valid"))
      end

      it "does not change any Tenant status" do
        expect {
          get(onboarding_confirmation_path(signed_id: "invalid-token-xyz"))
        }
          .not_to(change(Tenant, :count))
      end
    end

    context("with a valid signed_id for an already-confirmed tenant") do
      let(:tenant) { create(:tenant, :confirmed) }
      let(:signed_id) do
        # Build a signed_id as if for the confirm flow, but tenant is already confirmed
        tenant.gm_confirm_signed_id(expires_in: 72.hours)
      end

      it "renders the already_confirmed page" do
        get(onboarding_confirmation_path(signed_id: signed_id))
        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("You've already confirmed"))
      end

      it "does not record an additional FlowEvent" do
        expect {
          get(onboarding_confirmation_path(signed_id: signed_id))
        }
          .not_to(change(FlowEvent, :count))
      end
    end

    context("with an expired token") do
      let(:tenant) { create(:tenant) }
      let(:signed_id) do
        travel_to(73.hours.ago) do
          tenant.gm_confirm_signed_id(expires_in: 72.hours)
        end
      end

      it "renders the invalid page" do
        get(onboarding_confirmation_path(signed_id: signed_id))
        expect(response).to(have_http_status(:not_found))
        expect(response.body).to(include("no longer valid"))
      end

      it "does not confirm the tenant" do
        get(onboarding_confirmation_path(signed_id: signed_id))
        expect(tenant.reload.status).to(eq("pending_confirm"))
      end
    end
  end

  describe "POST /onboarding/confirmations/resend" do
    context("when email matches a pending_confirm tenant") do
      let!(:tenant) { create(:tenant, gm_email: "jane@smithtoyota.com") }

      it "enqueues a confirmation email" do
        expect {
          post(onboarding_resend_confirmation_path, params: {email: "jane@smithtoyota.com"})
        }
          .to(have_enqueued_mail(OnboardingMailer, :confirmation_email))
      end

      it "renders the resend_sent page" do
        post(onboarding_resend_confirmation_path, params: {email: "jane@smithtoyota.com"})
        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("Check your inbox"))
      end

      it "updates confirmation_sent_at" do
        freeze_time do
          post(onboarding_resend_confirmation_path, params: {email: "jane@smithtoyota.com"})
          expect(tenant.reload.confirmation_sent_at).to(be_within(1.second).of(Time.current))
        end
      end
    end

    context("when email does NOT match any tenant (anti-enumeration)") do
      it "does not enqueue any mail" do
        expect {
          post(onboarding_resend_confirmation_path, params: {email: "nobody@unknown.com"})
        }
          .not_to(have_enqueued_mail)
      end

      it "renders the same resend_sent page regardless (anti-enumeration)" do
        post(onboarding_resend_confirmation_path, params: {email: "nobody@unknown.com"})
        expect(response).to(have_http_status(:ok))
        expect(response.body).to(include("Check your inbox"))
      end
    end

    context("rate limiting") do
      let!(:tenant) { create(:tenant, gm_email: "jane@smithtoyota.com") }
      let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

      around do |example|
        original = Rails.cache
        Rails.cache = cache_store
        example.run
        Rails.cache = original
      end

      before do
        # Fill up the rate limit cache to the maximum (3)
        cache_store.write("resend_rate_limit:jane@smithtoyota.com", 3, expires_in: 1.hour)
      end

      it "does not enqueue mail when rate limit is exceeded" do
        expect {
          post(onboarding_resend_confirmation_path, params: {email: "jane@smithtoyota.com"})
        }
          .not_to(have_enqueued_mail)
      end

      it "still renders the resend_sent page (anti-enumeration; no 429 from cache check)" do
        post(onboarding_resend_confirmation_path, params: {email: "jane@smithtoyota.com"})
        expect(response).to(have_http_status(:ok))
      end
    end
  end
end
