FactoryBot.define do
  factory(:responsibility) do
    association(:tenant)
    association(:tenant_question)
    association(:primary_contact, factory: :contact)
    fallback_contact_emails { [] }
    gm_self_assigned { false }
    status { "active" }

    trait(:gm_self_assigned) do
      primary_contact { nil }
      gm_self_assigned { true }
    end

    trait(:superseded) do
      status { "superseded" }
    end
  end
end
