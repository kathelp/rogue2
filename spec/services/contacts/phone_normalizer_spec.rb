require "rails_helper"

RSpec.describe Contacts::PhoneNormalizer do
  describe ".call" do
    context("with a valid US phone number") do
      it "normalizes a 10-digit US number to E.164" do
        result = described_class.call("5125551234")

        expect(result).to(be_valid)
        expect(result.normalized).to(eq("+15125551234"))
      end

      it "normalizes a formatted 10-digit US number" do
        result = described_class.call("(512) 555-1234")

        expect(result).to(be_valid)
        expect(result.normalized).to(eq("+15125551234"))
      end

      it "normalizes an 11-digit number starting with 1" do
        result = described_class.call("1-512-555-1234")

        expect(result).to(be_valid)
        expect(result.normalized).to(eq("+15125551234"))
      end

      it "accepts an already-E.164 +1 number" do
        result = described_class.call("+15125551234")

        expect(result).to(be_valid)
        expect(result.normalized).to(eq("+15125551234"))
      end

      it "strips spaces, dots, and parens" do
        expect(described_class.call("+1.512.555.1234").normalized).to(eq("+15125551234"))
        expect(described_class.call("+1 (512) 555 1234").normalized).to(eq("+15125551234"))
      end
    end

    context("with invalid input") do
      it "returns an invalid Result for too-short input" do
        result = described_class.call("555-1234")

        expect(result).not_to(be_valid)
        expect(result.normalized).to(be_nil)
      end

      it "returns an invalid Result for too-long input" do
        result = described_class.call("+15125551234567")

        expect(result).not_to(be_valid)
        expect(result.normalized).to(be_nil)
      end

      it "returns an invalid Result for a non-US country code" do
        result = described_class.call("+447911123456")

        expect(result).not_to(be_valid)
        expect(result.normalized).to(be_nil)
      end

      it "returns an invalid Result for nil input" do
        result = described_class.call(nil)

        expect(result).not_to(be_valid)
        expect(result.normalized).to(be_nil)
      end

      it "returns an invalid Result for empty-string input" do
        result = described_class.call("")

        expect(result).not_to(be_valid)
        expect(result.normalized).to(be_nil)
      end

      it "returns an invalid Result for whitespace-only input" do
        result = described_class.call("   ")

        expect(result).not_to(be_valid)
        expect(result.normalized).to(be_nil)
      end

      it "returns an invalid Result for non-numeric input" do
        result = described_class.call("phone-please")

        expect(result).not_to(be_valid)
        expect(result.normalized).to(be_nil)
      end
    end

    it "returns a Contacts::PhoneNormalizer::Result struct" do
      result = described_class.call("5125551234")

      expect(result).to(be_a(Contacts::PhoneNormalizer::Result))
      expect(result).to(respond_to(:normalized))
      expect(result).to(respond_to(:valid?))
    end
  end
end
