require "rails_helper"

RSpec.describe Contacts::PhoneNormalizer do
  describe ".call" do
    it "normalizes a 10-digit US number to E.164" do
      expect(described_class.call("5125551234")).to(eq("+15125551234"))
    end

    it "normalizes a formatted 10-digit US number" do
      expect(described_class.call("(512) 555-1234")).to(eq("+15125551234"))
    end

    it "normalizes an 11-digit number starting with 1" do
      expect(described_class.call("1-512-555-1234")).to(eq("+15125551234"))
    end

    it "accepts an already-E.164 +1 number" do
      expect(described_class.call("+15125551234")).to(eq("+15125551234"))
    end

    it "strips spaces, dots, and parens" do
      expect(described_class.call("+1.512.555.1234")).to(eq("+15125551234"))
      expect(described_class.call("+1 (512) 555 1234")).to(eq("+15125551234"))
    end

    it "returns nil for too-short input" do
      expect(described_class.call("555-1234")).to(be_nil)
    end

    it "returns nil for too-long input" do
      expect(described_class.call("+15125551234567")).to(be_nil)
    end

    it "returns nil for non-US country code" do
      expect(described_class.call("+447911123456")).to(be_nil)
    end

    it "returns nil for blank input" do
      expect(described_class.call(nil)).to(be_nil)
      expect(described_class.call("")).to(be_nil)
      expect(described_class.call("   ")).to(be_nil)
    end

    it "returns nil for non-numeric input" do
      expect(described_class.call("phone-please")).to(be_nil)
    end
  end
end
