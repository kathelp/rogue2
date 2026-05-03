FactoryBot.define do
  factory :submission do
    association :tenant
    association :request
    association :submission_prompt
    association :submitted_by_contact, factory: :contact
    value { 42_500.0 }
    notes { nil }
    period_starting { Date.new(2026, 5, 1) }
    submitted_at { Time.current }
  end
end
