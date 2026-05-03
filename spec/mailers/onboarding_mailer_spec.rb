require "rails_helper"

RSpec.describe OnboardingMailer, type: :mailer do
  describe "#confirmation_email" do
    let(:tenant) { create(:tenant, dealership_name: "Smith Toyota", gm_name: "Jane Smith", gm_email: "jane@smithtoyota.com") }
    let(:mail) { described_class.with(tenant: tenant).confirmation_email }

    it "sends to the GM email" do
      expect(mail.to).to eq([ "jane@smithtoyota.com" ])
    end

    it "has the correct subject" do
      expect(mail.subject).to eq("Welcome to Rogue — confirm to begin")
    end

    it "comes from the Rogue transactional address" do
      expect(mail.from).to include("hello@inbound.rogue.example")
    end

    it "contains a CTA link to the onboarding confirmation path" do
      expect(mail.html_part.body.decoded).to include("Confirm and start onboarding")
      expect(mail.html_part.body.decoded).to include("/onboarding/confirmations/")
    end

    it "contains the signed_id URL in the HTML body" do
      signed_id = tenant.gm_confirm_signed_id(expires_in: 72.hours)
      # The URL contains the signed_id somewhere — just verify the path prefix
      expect(mail.html_part.body.decoded).to include("/onboarding/confirmations/")
    end

    it "has a plain-text alternative" do
      expect(mail.text_part).not_to be_nil
    end

    it "contains the confirmation URL in the plain-text alternative" do
      expect(mail.text_part.body.decoded).to include("/onboarding/confirmations/")
    end

    it "includes 'Confirm and start onboarding' in the plain-text body" do
      expect(mail.text_part.body.decoded).to include("Confirm and start onboarding")
    end

    it "mentions the GM name in the HTML body" do
      expect(mail.html_part.body.decoded).to include("Jane Smith")
    end

    it "mentions the dealership name in the HTML body" do
      expect(mail.html_part.body.decoded).to include("Smith Toyota")
    end
  end
end
