FactoryBot.define do
  factory :source do
    association :tenant
    domain { "marketing" }
    sequence(:responsibility_key) { |n| "marketing_strategy_#{n}" }

    trait :configured do
      submission_method { "form" }
      configured_at { Time.current }
      association :configured_by_contact, factory: :contact
    end
  end
end
