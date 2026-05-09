require "rails_helper"

RSpec.describe Contact, type: :model do
  subject(:contact) { build(:contact) }

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  it { is_expected.to(belong_to(:tenant)) }
  it { is_expected.to(belong_to(:vendor).optional) }

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  it { is_expected.to(validate_presence_of(:email)) }
  it { is_expected.to(validate_presence_of(:classification)) }

  # --------------------------------------------------------------------------
  # find_or_create_for_email
  # --------------------------------------------------------------------------
  describe ".find_or_create_for_email" do
    let(:tenant) { create(:tenant) }

    it "creates a contact with the given classification" do
      contact = Contact.find_or_create_for_email(
        tenant: tenant,
        email: "alex@smithtoyota.com",
        classification: :internal_staff
      )
      expect(contact).to(be_persisted)
      expect(contact.classification).to(eq("internal_staff"))
    end

    it "normalizes the email to lowercase" do
      contact = Contact.find_or_create_for_email(
        tenant: tenant,
        email: "Alex@SmithToyota.com",
        classification: :internal_staff
      )
      expect(contact.email_normalized).to(eq("alex@smithtoyota.com"))
    end

    it "is idempotent — returns existing contact on re-call" do
      Contact.find_or_create_for_email(tenant: tenant, email: "alex@smithtoyota.com", classification: :internal_staff)
      expect {
        Contact.find_or_create_for_email(tenant: tenant, email: "alex@smithtoyota.com", classification: :internal_staff)
      }
        .not_to(change(Contact, :count))
    end

    it "is scoped to the tenant — same email for different tenant creates a new contact" do
      other_tenant = create(:tenant)
      Contact.find_or_create_for_email(tenant: tenant, email: "alex@smithtoyota.com", classification: :internal_staff)
      expect {
        Contact.find_or_create_for_email(
          tenant: other_tenant,
          email: "alex@smithtoyota.com",
          classification: :internal_staff
        )
      }
        .to(change(Contact, :count).by(1))
    end

    it "optionally sets the vendor" do
      vendor = create(:vendor)
      contact = Contact.find_or_create_for_email(
        tenant: tenant,
        email: "rep@vendor.com",
        classification: :vendor_user,
        vendor: vendor
      )
      expect(contact.vendor).to(eq(vendor))
    end
  end

  # --------------------------------------------------------------------------
  # Verification (TASK-008 Phase 1)
  # --------------------------------------------------------------------------
  describe "#verified?" do
    let(:tenant) { create(:tenant) }

    it "is true when first_name, last_name, and phone are all present" do
      contact = build(:contact, :verified, tenant: tenant)
      expect(contact.verified?).to(be(true))
    end

    it "is false when first_name is blank" do
      contact = build(:contact, :verified, tenant: tenant, first_name: nil)
      expect(contact.verified?).to(be(false))
    end

    it "is false when last_name is blank" do
      contact = build(:contact, :verified, tenant: tenant, last_name: "")
      expect(contact.verified?).to(be(false))
    end

    it "is false when phone is blank" do
      contact = build(:contact, :verified, tenant: tenant, phone: nil)
      expect(contact.verified?).to(be(false))
    end

    it "is false on a newly-promoted CC'd contact (all three blank)" do
      contact = Contact.find_or_create_for_email(
        tenant: tenant,
        email: "linda@vendor.com",
        classification: :vendor_user
      )
      expect(contact.verified?).to(be(false))
    end
  end

  describe "scopes" do
    let(:tenant) { create(:tenant) }

    it ":verified returns contacts with all three identity fields present" do
      verified = create(:contact, :verified, tenant: tenant)
      _unverified = create(:contact, tenant: tenant)
      expect(Contact.verified).to(contain_exactly(verified))
    end

    it ":unverified returns contacts missing any identity field" do
      _verified = create(:contact, :verified, tenant: tenant)
      unverified = create(:contact, tenant: tenant)
      partially_verified = create(:contact, :verified, tenant: tenant, phone: nil)
      expect(Contact.unverified).to(contain_exactly(unverified, partially_verified))
    end

    it ":verified and :unverified are inverse — every contact lands in exactly one" do
      verified = create(:contact, :verified, tenant: tenant)
      unverified = create(:contact, tenant: tenant)
      expect(Contact.verified + Contact.unverified).to(contain_exactly(verified, unverified))
    end
  end

  describe "phone encryption" do
    it "round-trips through non-deterministic encryption" do
      contact = create(:contact, :verified, phone: "+15125551234")
      contact.reload
      expect(contact.phone).to(eq("+15125551234"))
    end
  end

  describe "blank identity field normalization" do
    let(:tenant) { create(:tenant) }

    it "stores blank strings as nil for first_name, last_name, phone" do
      contact = create(:contact, tenant: tenant, first_name: "", last_name: "  ", phone: "")
      contact.reload
      expect(contact.first_name).to(be_nil)
      expect(contact.last_name).to(be_nil)
      expect(contact.phone).to(be_nil)
    end
  end
end
