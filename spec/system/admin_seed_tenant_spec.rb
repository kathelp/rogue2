require "rails_helper"

RSpec.describe "Admin seed tenant", type: :system do
  before do
    driven_by(:rack_test)
  end

  def admin_basic_auth
    page.driver.browser.basic_authorize("admin", "admin-test-password")
  end

  describe "seeding a tenant via the admin form" do
    it "creates the tenant, shows flash, and renders the show page" do
      admin_basic_auth

      visit(new_admin_tenant_path)

      expect(page).to(have_field("Dealership name"))
      expect(page).to(have_field("GM name"))
      expect(page).to(have_field("GM email"))
      expect(page).to(have_button("Seed tenant"))

      fill_in("Dealership name", with: "Smith Toyota")
      fill_in("GM name", with: "Jane Smith")
      fill_in("GM email", with: "jane@smithtoyota.com")
      click_button("Seed tenant")

      # Redirected to show page
      expect(page).to(have_text("Smith Toyota"))
      expect(page).to(have_text("Jane Smith"))
      expect(page).to(have_text("pending_confirm"))

      # Flash notice
      expect(page).to(have_text("Seeded Smith Toyota"))
      expect(page).to(have_text("jane@smithtoyota.com"))
    end

    it "queues a confirmation email after seeding" do
      admin_basic_auth

      expect {
        visit(new_admin_tenant_path)
        fill_in("Dealership name", with: "Smith Toyota")
        fill_in("GM name", with: "Jane Smith")
        fill_in("GM email", with: "jane@smithtoyota.com")
        click_button("Seed tenant")
      }
        .to(have_enqueued_mail(OnboardingMailer, :confirmation_email))
    end

    it "re-renders the form with errors when dealership name is blank" do
      admin_basic_auth

      visit(new_admin_tenant_path)
      fill_in("GM name", with: "Jane Smith")
      fill_in("GM email", with: "jane@smithtoyota.com")
      click_button("Seed tenant")

      expect(page).to(have_button("Seed tenant"))
      expect(page).to(have_text("Dealership name"))
    end
  end

  describe "GM confirms via magic link" do
    let!(:tenant) { create(:tenant, gm_email: "jane@smithtoyota.com") }

    it "transitions tenant to confirmed and shows confirmation page" do
      signed_id = tenant.gm_confirm_signed_id(expires_in: 72.hours)

      visit(onboarding_confirmation_path(signed_id: signed_id))

      expect(page).to(have_text("You're confirmed."))
      expect(page).to(have_text("inbox"))

      expect(tenant.reload.status).to(eq("confirmed"))
      expect(tenant.reload.confirmed_at).not_to(be_nil)
    end

    it "shows the already-confirmed page when the link is clicked a second time" do
      # Confirm the tenant first
      tenant.confirm!
      signed_id = tenant.gm_confirm_signed_id(expires_in: 72.hours)

      visit(onboarding_confirmation_path(signed_id: signed_id))

      expect(page).to(have_text("already confirmed"))
    end

    it "shows the invalid page for an expired/invalid token" do
      visit(onboarding_confirmation_path(signed_id: "not-a-valid-token"))

      expect(page).to(have_text("no longer valid"))
    end
  end
end
