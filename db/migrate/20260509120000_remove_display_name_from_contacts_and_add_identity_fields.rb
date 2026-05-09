class RemoveDisplayNameFromContactsAndAddIdentityFields < ActiveRecord::Migration[8.1]
  def change
    remove_column(:contacts, :display_name, :string)

    add_column(:contacts, :first_name, :string)
    add_column(:contacts, :last_name, :string)
    add_column(:contacts, :phone, :string)
  end
end
