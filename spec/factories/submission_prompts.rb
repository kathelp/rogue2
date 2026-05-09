FactoryBot.define do
  factory(:submission_prompt) do
    association(:tenant)
    association(:request)
    scheduled_for { 1.month.from_now }
    status { "pending" }
  end
end
