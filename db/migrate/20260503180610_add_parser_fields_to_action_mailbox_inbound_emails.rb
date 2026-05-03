class AddParserFieldsToActionMailboxInboundEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :action_mailbox_inbound_emails, :parser_intent, :string
    add_column :action_mailbox_inbound_emails, :parser_confidence, :string
    add_column :action_mailbox_inbound_emails, :parser_warnings, :jsonb, null: false, default: []
  end
end
