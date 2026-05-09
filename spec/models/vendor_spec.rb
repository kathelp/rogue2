require "rails_helper"

RSpec.describe Vendor, type: :model do
  subject(:vendor) { build(:vendor) }

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  it { is_expected.to(validate_presence_of(:name)) }
  it { is_expected.to(validate_presence_of(:state)) }
  it { is_expected.to(validate_presence_of(:source)) }

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  it { is_expected.to(belong_to(:parent_vendor).class_name("Vendor").optional) }
  it { is_expected.to(belong_to(:created_by_tenant).class_name("Tenant").optional) }
  it { is_expected.to(have_many(:contacts)) }

  # --------------------------------------------------------------------------
  # matching_domain scope
  # --------------------------------------------------------------------------
  describe ".matching_domain" do
    let!(:vinsolutions) { create(:vendor, name: "VinSolutions", domains: ["vinsolutions.com", "vinsolutions.net"]) }
    let!(:other) { create(:vendor, name: "Other Vendor", domains: ["othervendor.com"]) }

    it "returns vendor when domain is in the array" do
      expect(Vendor.matching_domain("vinsolutions.com")).to(include(vinsolutions))
    end

    it "does not return vendor when domain is not in the array" do
      expect(Vendor.matching_domain("notinlist.com")).not_to(include(vinsolutions))
    end

    it "handles case-insensitive lookup" do
      # domain in array is lowercased; lookup input is lowercased by the scope
      expect(Vendor.matching_domain("VinSolutions.com")).to(include(vinsolutions))
    end

    it "returns the correct vendor for a second domain in the array" do
      expect(Vendor.matching_domain("vinsolutions.net")).to(include(vinsolutions))
    end

    it "does not cross-match to unrelated vendors" do
      expect(Vendor.matching_domain("vinsolutions.com")).not_to(include(other))
    end
  end

  # --------------------------------------------------------------------------
  # bootstrap! class method
  # --------------------------------------------------------------------------
  describe ".bootstrap!" do
    it "creates a vendor with given attributes" do
      vendor = Vendor.bootstrap!(name: "NewVendor", domains: ["newvendor.com"], source: :seed)
      expect(vendor).to(be_persisted)
      expect(vendor.name).to(eq("NewVendor"))
      expect(vendor.domains).to(include("newvendor.com"))
    end

    it "is idempotent — returns existing vendor on re-call" do
      Vendor.bootstrap!(name: "ExistingVendor", domains: ["existing.com"], source: :seed)
      expect { Vendor.bootstrap!(name: "ExistingVendor", domains: ["existing.com"], source: :seed) }
        .not_to(change(Vendor, :count))
    end
  end
end
