# VendorInferenceService
#
# Classifies an email address as internal staff, vendor user, or unknown,
# based on the email domain.
#
# Usage:
#   result = VendorInferenceService.call(email: "alex@smithtoyota.com", tenant: tenant)
#   result.classification  # => :internal_staff | :vendor_user | :unknown
#   result.vendor          # => Vendor | nil
#   result.requires_clarification  # => Boolean
#
# Per architecture design A3.
class VendorInferenceService
  Result = Struct.new(
    :classification,          # :internal_staff | :vendor_user | :unknown
    :vendor,                  # Vendor | nil
    :requires_clarification,  # Boolean
    keyword_init: true
  )

  def self.call(email:, tenant:)
    new(email: email, tenant: tenant).call
  end

  def initialize(email:, tenant:)
    @email  = email.to_s.downcase.strip
    @tenant = tenant
  end

  def call
    return internal_staff_result if internal_domain?

    vendor = Vendor.active_vendors.matching_domain(email_domain).first
    return vendor_result(vendor) if vendor

    unknown_result
  end

  private

  def email_domain
    @email_domain ||= @email.split("@", 2).last.to_s.downcase.strip
  end

  def gm_domain
    @gm_domain ||= @tenant.gm_email_normalized.split("@", 2).last.to_s.downcase.strip
  end

  def internal_domain?
    email_domain == gm_domain
  end

  def internal_staff_result
    Result.new(classification: :internal_staff, vendor: nil, requires_clarification: false)
  end

  def vendor_result(vendor)
    Result.new(classification: :vendor_user, vendor: vendor, requires_clarification: false)
  end

  def unknown_result
    Result.new(classification: :unknown, vendor: nil, requires_clarification: true)
  end
end
