FactoryBot.define do
  factory :contact do
    association :tenant
    sequence(:email) { |n| "alex#{n}@smithtoyota.com" }
    classification { "internal_staff" }

    trait :vendor_user do
      association :vendor
      classification { "vendor_user" }
      sequence(:email) { |n| "rep#{n}@somevendor.com" }
    end

    trait :unknown do
      classification { "unknown" }
      sequence(:email) { |n| "unknown#{n}@unknowndomain.com" }
    end
  end
end
