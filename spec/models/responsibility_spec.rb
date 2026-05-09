require "rails_helper"

RSpec.describe Responsibility, type: :model do
  subject(:responsibility) { build(:responsibility) }

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  it { is_expected.to(belong_to(:tenant)) }
  it { is_expected.to(belong_to(:tenant_question)) }
  it { is_expected.to(belong_to(:primary_contact).class_name("Contact").optional) }

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  it { is_expected.to(validate_presence_of(:tenant)) }
  it { is_expected.to(validate_presence_of(:tenant_question)) }
  it { is_expected.to(validate_presence_of(:status)) }

  # --------------------------------------------------------------------------
  # primary_email
  # --------------------------------------------------------------------------
  describe "#primary_email" do
    context("when gm_self_assigned is true") do
      it "returns the tenant's gm_email_normalized" do
        tenant = create(:tenant, gm_email: "jane@smithtoyota.com")
        tq = create(:tenant_question, tenant: tenant)
        responsibility = create(:responsibility, :gm_self_assigned, tenant: tenant, tenant_question: tq)
        expect(responsibility.primary_email).to(eq("jane@smithtoyota.com"))
      end
    end

    context("when primary_contact is set") do
      it "returns the primary contact's email_normalized" do
        tenant = create(:tenant)
        contact = create(:contact, tenant: tenant, email: "alex@smithtoyota.com")
        tq = create(:tenant_question, tenant: tenant)
        responsibility = create(:responsibility, tenant: tenant, tenant_question: tq, primary_contact: contact)
        expect(responsibility.primary_email).to(eq("alex@smithtoyota.com"))
      end
    end

    context("when neither gm_self_assigned nor primary_contact") do
      it "returns nil" do
        responsibility = build(:responsibility, primary_contact: nil, gm_self_assigned: false)
        expect(responsibility.primary_email).to(be_nil)
      end
    end
  end

  # --------------------------------------------------------------------------
  # Status enum
  # --------------------------------------------------------------------------
  describe "status enum" do
    it "defaults to active" do
      expect(build(:responsibility).status).to(eq("active"))
    end

    it "includes all expected statuses" do
      expect(Responsibility.statuses.keys).to(include("active", "superseded"))
    end
  end
end
