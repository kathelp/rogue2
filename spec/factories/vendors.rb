FactoryBot.define do
  factory :vendor do
    sequence(:name) { |n| "Test Vendor #{n}" }
    sequence(:domains) { |n| [ "testvendor#{n}.com" ] }
    aliases { [] }
    categories { [] }
    state { "active" }
    source { "seed" }
  end
end
