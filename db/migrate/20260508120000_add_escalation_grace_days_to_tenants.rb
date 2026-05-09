class AddEscalationGraceDaysToTenants < ActiveRecord::Migration[8.0]
  def change
    add_column(:tenants, :escalation_due_soon_grace_days, :integer)
    add_column(:tenants, :escalation_overdue_grace_days, :integer)
    add_column(:tenants, :escalation_fallback_grace_days, :integer)
    add_column(:tenants, :escalation_gm_grace_days, :integer)
  end
end
