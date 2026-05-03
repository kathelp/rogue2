require "rails_helper"

RSpec.describe VendorInferenceService, type: :service do
  let(:tenant) do
    create(:tenant,
           dealership_name: "Smith Toyota",
           gm_email:        "jane@smithtoyota.com")
  end

  describe ".call" do
    context "when the email domain matches the GM's domain" do
      it "returns :internal_staff classification" do
        result = described_class.call(email: "alex@smithtoyota.com", tenant: tenant)

        expect(result.classification).to eq(:internal_staff)
        expect(result.vendor).to be_nil
        expect(result.requires_clarification).to be false
      end

      it "is case-insensitive on domain comparison" do
        result = described_class.call(email: "ALEX@SmithToyota.COM", tenant: tenant)

        expect(result.classification).to eq(:internal_staff)
      end
    end

    context "when the email domain matches an active Vendor" do
      let!(:vendor) do
        create(:vendor,
               name:    "VinSolutions",
               domains: [ "vinsolutions.com" ],
               state:   "active",
               source:  "seed")
      end

      it "returns :vendor_user classification with the matched vendor" do
        result = described_class.call(email: "rep@vinsolutions.com", tenant: tenant)

        expect(result.classification).to eq(:vendor_user)
        expect(result.vendor).to eq(vendor)
        expect(result.requires_clarification).to be false
      end

      it "is case-insensitive on vendor domain matching" do
        result = described_class.call(email: "rep@VINSOLUTIONS.COM", tenant: tenant)

        expect(result.classification).to eq(:vendor_user)
        expect(result.vendor).to eq(vendor)
      end

      it "does not match archived vendors" do
        vendor.update!(state: "archived")
        result = described_class.call(email: "rep@vinsolutions.com", tenant: tenant)

        expect(result.classification).to eq(:unknown)
        expect(result.vendor).to be_nil
      end
    end

    context "when the domain is unknown" do
      it "returns :unknown classification and requires clarification" do
        result = described_class.call(email: "alex@unknownvendor.com", tenant: tenant)

        expect(result.classification).to eq(:unknown)
        expect(result.vendor).to be_nil
        expect(result.requires_clarification).to be true
      end
    end
  end
end
