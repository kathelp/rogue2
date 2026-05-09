FactoryBot.define do
  factory(:skipped_question) do
    association(:tenant)
    association(:tenant_question)
    skipped_at { Time.current }
  end
end
