# Normalizes a US phone number to E.164 (+1XXXXXXXXXX).
#
# Returns a Result struct with two members:
#   - normalized: the E.164 string when valid, nil otherwise
#   - valid?:     true when the input reduced cleanly to a US E.164 number
#
# The controller branches on .valid? and renders an HTTP 422 with a
# field-level error when false. US-only at MVP per the FEAT-006
# architecture doc; if international support arrives, swap for the
# `phonelib` gem and a richer contract.
module Contacts
  module PhoneNormalizer
    Result = Struct.new(:normalized, :valid?, keyword_init: true)

    def self.call(input)
      return Result.new(normalized: nil, valid?: false) if input.blank?

      digits = input.to_s.gsub(/\D/, "")

      case digits.length
      when 10
        Result.new(normalized: "+1#{digits}", valid?: true)
      when 11
        if digits.start_with?("1")
          Result.new(normalized: "+#{digits}", valid?: true)
        else
          Result.new(normalized: nil, valid?: false)
        end
      else
        Result.new(normalized: nil, valid?: false)
      end
    end
  end
end
