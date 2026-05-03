FactoryBot.define do
  factory :flow_event do
    association :tenant
    event_type { "tenant.seeded" }
    payload { {} }
    occurred_at { Time.current }
  end
end
