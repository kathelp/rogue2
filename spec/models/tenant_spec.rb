require "rails_helper"

RSpec.describe Tenant, type: :model do
  subject(:tenant) { build(:tenant) }

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  it { is_expected.to have_many(:contacts).dependent(:destroy) }
  it { is_expected.to have_many(:tenant_questions).dependent(:destroy) }
  it { is_expected.to have_many(:responsibilities).dependent(:destroy) }
  it { is_expected.to have_many(:flow_events).dependent(:destroy) }

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  it { is_expected.to validate_presence_of(:dealership_name) }
  it { is_expected.to validate_presence_of(:gm_name) }
  it { is_expected.to validate_presence_of(:gm_email) }

  # --------------------------------------------------------------------------
  # gm_email normalization
  # --------------------------------------------------------------------------
  describe "gm_email normalization" do
    it "downcases and strips on create" do
      tenant = create(:tenant, gm_email: "  Jane@SmithToyota.com  ")
      expect(tenant.gm_email_normalized).to eq("jane@smithtoyota.com")
    end

    it "sets gm_email_normalized to match normalized gm_email" do
      tenant = create(:tenant, gm_email: "UPPER@CASE.COM")
      expect(tenant.gm_email_normalized).to eq("upper@case.com")
    end
  end

  # --------------------------------------------------------------------------
  # onboarding_token generation
  # --------------------------------------------------------------------------
  describe "onboarding_token" do
    it "is generated on create" do
      tenant = create(:tenant)
      expect(tenant.onboarding_token).to be_present
      expect(tenant.onboarding_token.length).to eq(16)
    end

    it "is unique across tenants" do
      t1 = create(:tenant)
      t2 = create(:tenant)
      expect(t1.onboarding_token).not_to eq(t2.onboarding_token)
    end

    it "raises on duplicate token (validation or DB uniqueness)" do
      t1 = create(:tenant)
      # Rails model validation catches duplicates first; DB unique index is a backup.
      expect {
        create(:tenant, onboarding_token: t1.onboarding_token)
      }.to raise_error(ActiveRecord::RecordInvalid, /Onboarding token/)
    end
  end

  # --------------------------------------------------------------------------
  # Status enum
  # --------------------------------------------------------------------------
  describe "status enum" do
    it "defaults to pending_confirm" do
      expect(build(:tenant).status).to eq("pending_confirm")
    end

    it "includes all expected statuses" do
      expect(Tenant.statuses.keys).to include("seeded", "pending_confirm", "confirmed", "active")
    end
  end

  # --------------------------------------------------------------------------
  # confirm!
  # --------------------------------------------------------------------------
  describe "#confirm!" do
    let(:tenant) { create(:tenant, status: :pending_confirm) }

    it "sets status to confirmed" do
      tenant.confirm!
      expect(tenant.reload.status).to eq("confirmed")
    end

    it "sets confirmed_at" do
      now = Time.current
      travel_to(now) do
        tenant.confirm!
        expect(tenant.reload.confirmed_at).to be_within(1.second).of(now)
      end
    end

    it "returns false if already confirmed" do
      tenant.update!(status: :confirmed, confirmed_at: Time.current)
      result = tenant.confirm!
      expect(result).to eq(false)
    end
  end

  # --------------------------------------------------------------------------
  # signed_id round-trip
  # --------------------------------------------------------------------------
  describe "signed_id helpers" do
    let(:tenant) { create(:tenant) }

    it "round-trips gm_confirm signed_id" do
      signed = tenant.gm_confirm_signed_id
      found = Tenant.find_by_gm_confirm_signed_id!(signed)
      expect(found).to eq(tenant)
    end

    it "raises on wrong purpose" do
      signed = tenant.signed_id(purpose: :wrong_purpose)
      expect {
        Tenant.find_by_gm_confirm_signed_id!(signed)
      }.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    end
  end

  # --------------------------------------------------------------------------
  # in_onboarding_silence scope
  # --------------------------------------------------------------------------
  describe ".in_onboarding_silence" do
    it "returns confirmed tenants with no gm reply in the threshold window" do
      silent_tenant = create(:tenant, :confirmed, last_gm_reply_at: nil)
      active_tenant = create(:tenant, :confirmed, last_gm_reply_at: 1.hour.ago)

      expect(Tenant.in_onboarding_silence).to include(silent_tenant)
      expect(Tenant.in_onboarding_silence).not_to include(active_tenant)
    end
  end

  # --------------------------------------------------------------------------
  # next_question_cadence_gap
  # --------------------------------------------------------------------------
  describe "#next_question_cadence_gap" do
    it "returns 12 hours for reply < 1 hour ago" do
      tenant = build(:tenant, last_gm_reply_at: 30.minutes.ago)
      expect(tenant.next_question_cadence_gap).to eq(12.hours)
    end

    it "returns 24 hours for reply between 1h and 24h ago" do
      tenant = build(:tenant, last_gm_reply_at: 4.hours.ago)
      expect(tenant.next_question_cadence_gap).to eq(24.hours)
    end

    it "returns 48 hours for reply between 24h and 72h ago" do
      tenant = build(:tenant, last_gm_reply_at: 50.hours.ago)
      expect(tenant.next_question_cadence_gap).to eq(48.hours)
    end

    it "returns nil for reply >= 72h ago (silence state)" do
      tenant = build(:tenant, last_gm_reply_at: 73.hours.ago)
      expect(tenant.next_question_cadence_gap).to be_nil
    end

    it "returns nil when last_gm_reply_at is nil" do
      tenant = build(:tenant, last_gm_reply_at: nil)
      expect(tenant.next_question_cadence_gap).to be_nil
    end
  end
end
