class Current < ActiveSupport::CurrentAttributes
  attribute :tenant
  # Future: actor (Contact / staff identifier), request_id
end
