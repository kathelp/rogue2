FactoryBot.define do
  factory(:tenant_question) do
    association(:tenant)
    catalog_version { 1 }
    domain { "marketing" }
    sequence(:key) { |n| "marketing_question_#{n}" }
    sequence(:position) { |n| n }
    prompt { "Who controls your marketing strategy at Smith Toyota?" }
    deliverable { "marketing strategy report" }
    default_cadence { "monthly" }
    status { "pending" }

    trait(:sent) do
      status { "sent" }
      sent_at { 1.hour.ago }
    end

    trait(:answered) do
      status { "answered" }
      sent_at { 2.hours.ago }
      answered_at { 1.hour.ago }
    end

    trait(:skipped) do
      status { "skipped" }
      sent_at { 1.hour.ago }
    end
  end
end
