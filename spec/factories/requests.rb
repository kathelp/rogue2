FactoryBot.define do
  factory :request do
    association :tenant
    association :source
    metric_key { "strategy_summary" }
    cadence { "monthly" }
    next_due_at { 1.month.from_now }
  end
end
