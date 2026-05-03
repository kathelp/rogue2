require "rails_helper"

RSpec.describe Rogue::QuestionCatalog::Marketing::V1 do
  let(:tenant) { create(:tenant, dealership_name: "Smith Toyota") }

  describe "QUESTIONS constant" do
    it "has at least 4 questions" do
      expect(described_class::QUESTIONS.length).to be >= 4
    end

    it "each question has required keys" do
      described_class::QUESTIONS.each do |q|
        expect(q).to include(:key, :position, :prompt, :default_cadence, :metrics)
      end
    end

    it "positions are unique" do
      positions = described_class::QUESTIONS.map { |q| q[:position] }
      expect(positions.uniq).to eq(positions)
    end

    it "keys are unique" do
      keys = described_class::QUESTIONS.map { |q| q[:key] }
      expect(keys.uniq).to eq(keys)
    end
  end

  describe ".materialize_for" do
    it "creates TenantQuestion rows for all questions" do
      expect {
        described_class.materialize_for(tenant: tenant)
      }.to change(TenantQuestion, :count).by(described_class::QUESTIONS.length)
    end

    it "sets the catalog version on each question" do
      described_class.materialize_for(tenant: tenant)
      expect(tenant.tenant_questions.pluck(:catalog_version).uniq).to eq([ described_class::VERSION ])
    end

    it "substitutes dealership_name in the prompt" do
      described_class.materialize_for(tenant: tenant)
      questions_with_name = tenant.tenant_questions.select { |q| q.prompt.include?("Smith Toyota") }
      expect(questions_with_name).not_to be_empty
    end

    it "is idempotent — re-calling does not create duplicate rows" do
      described_class.materialize_for(tenant: tenant)
      expect {
        described_class.materialize_for(tenant: tenant)
      }.not_to change(TenantQuestion, :count)
    end

    it "sets status to pending for new questions" do
      described_class.materialize_for(tenant: tenant)
      expect(tenant.tenant_questions.pluck(:status).uniq).to eq([ "pending" ])
    end

    it "sets the domain to marketing for all questions" do
      described_class.materialize_for(tenant: tenant)
      expect(tenant.tenant_questions.pluck(:domain).uniq).to eq([ "marketing" ])
    end
  end

  describe ".metrics_for" do
    it "returns the metrics array for a known question key" do
      metrics = described_class.metrics_for(key: "marketing_strategy")
      expect(metrics).to be_an(Array)
      expect(metrics.first).to include(:key, :cadence)
    end

    it "returns an empty array for an unknown key" do
      expect(described_class.metrics_for(key: "definitely_not_a_real_key")).to eq([])
    end
  end
end
