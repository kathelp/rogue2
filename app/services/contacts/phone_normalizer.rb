# Normalizes a US phone number to E.164 (+1XXXXXXXXXX).
# Returns nil for blank, non-numeric, or non-US-shaped input. The caller
# decides what to do with nil — typically render a validation error.
#
# US-only at MVP per the FEAT-006 architecture doc. If/when international
# support arrives, swap this for the `phonelib` gem and a richer contract.
module Contacts
  module PhoneNormalizer
    def self.call(input)
      digits = input.to_s.gsub(/\D/, "")
      digits = digits.delete_prefix("1") if digits.length == 11 && digits.start_with?("1")
      return nil unless digits.length == 10

      "+1#{digits}"
    end
  end
end
