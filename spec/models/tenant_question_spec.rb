require "rails_helper"

RSpec.describe TenantQuestion, type: :model do
  subject(:tenant_question) { build(:tenant_question) }

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  it { is_expected.to(belong_to(:tenant)) }
  it { is_expected.to(have_many(:responsibilities).dependent(:destroy)) }
  it { is_expected.to(have_many(:skipped_questions).dependent(:destroy)) }

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  it { is_expected.to(validate_presence_of(:key)) }
  it { is_expected.to(validate_presence_of(:prompt)) }
  it { is_expected.to(validate_presence_of(:default_cadence)) }
  it { is_expected.to(validate_presence_of(:catalog_version)) }

  # --------------------------------------------------------------------------
  # Uniqueness on (tenant_id, key, catalog_version)
  # --------------------------------------------------------------------------
  describe "uniqueness constraint" do
    let(:tenant) { create(:tenant) }

    it "prevents duplicate (tenant, key, catalog_version)" do
      create(:tenant_question, tenant: tenant, key: "marketing_strategy", catalog_version: 1)
      expect {
        create(:tenant_question, tenant: tenant, key: "marketing_strategy", catalog_version: 1)
      }
        .to(raise_error(ActiveRecord::RecordInvalid))
    end

    it "allows same key for different tenants" do
      other_tenant = create(:tenant)
      create(:tenant_question, tenant: tenant, key: "marketing_strategy", catalog_version: 1)
      expect {
        create(:tenant_question, tenant: other_tenant, key: "marketing_strategy", catalog_version: 1)
      }
        .not_to(raise_error)
    end

    it "allows same key for different catalog versions" do
      create(:tenant_question, tenant: tenant, key: "marketing_strategy", catalog_version: 1)
      expect {
        create(:tenant_question, tenant: tenant, key: "marketing_strategy", catalog_version: 2)
      }
        .not_to(raise_error)
    end
  end

  # --------------------------------------------------------------------------
  # Status enum
  # --------------------------------------------------------------------------
  describe "status enum" do
    it "defaults to pending" do
      expect(build(:tenant_question).status).to(eq("pending"))
    end

    it "includes all expected statuses" do
      expect(TenantQuestion.statuses.keys).to(include("pending", "sent", "answered", "skipped"))
    end
  end
end
