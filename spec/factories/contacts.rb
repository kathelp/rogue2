FactoryBot.define do
  factory(:contact) do
    association(:tenant)
    sequence(:email) { |n| "alex#{n}@smithtoyota.com" }
    classification { "internal_staff" }

    trait(:vendor_user) do
      association(:vendor)
      classification { "vendor_user" }
      sequence(:email) { |n| "rep#{n}@somevendor.com" }
    end

    trait(:unknown) do
      classification { "unknown" }
      sequence(:email) { |n| "unknown#{n}@unknowndomain.com" }
    end

    trait(:verified) do
      sequence(:first_name) { |n| "Alex#{n}" }
      last_name { "Rivera" }
      phone { "+15125550100" }
    end

    trait(:unverified) do
      first_name { nil }
      last_name { nil }
      phone { nil }
    end
  end
end
