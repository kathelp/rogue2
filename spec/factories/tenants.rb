FactoryBot.define do
  factory :tenant do
    sequence(:dealership_name) { |n| "Smith Toyota #{n}" }
    gm_name { "Jane Smith" }
    sequence(:gm_email) { |n| "jane#{n}@smithtoyota.com" }
    status { "pending_confirm" }
    first_question_delay_minutes { 60 }
    next_question_delay_hours { 24 }
    time_zone { "America/New_York" }
    question_catalog_version { 1 }

    trait :confirmed do
      status { "confirmed" }
      confirmed_at { 1.day.ago }
    end

    trait :active do
      status { "active" }
      confirmed_at { 7.days.ago }
    end
  end
end
