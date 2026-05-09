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
end
