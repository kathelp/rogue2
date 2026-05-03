class FlowEvent < ApplicationRecord
  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :tenant, optional: true

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :event_type, presence: true
  validates :occurred_at, presence: true

  # --------------------------------------------------------------------------
  # Class methods
  # --------------------------------------------------------------------------
  # Single write path for recording flow events. Called inside the transaction
  # performing the domain mutation so the event is committed atomically.
  #
  # Usage:
  #   FlowEvent.record!(
  #     event_type: "tenant.confirmed",
  #     tenant: current_tenant,
  #     subject: current_tenant,
  #     actor: nil,
  #     payload: { ip: request.remote_ip }
  #   )
  def self.record!(event_type:, tenant: Current.tenant, actor: nil, subject: nil, payload: {}, occurred_at: Time.current)
    create!(
      event_type: event_type,
      tenant: tenant,
      actor_type: actor_type_for(actor),
      actor_id: actor_id_for(actor),
      subject_type: subject_type_for(subject),
      subject_id: subject_id_for(subject),
      payload: payload || {},
      occurred_at: occurred_at
    )
  end

  private_class_method def self.actor_type_for(actor)
    actor&.class&.name
  end

  private_class_method def self.actor_id_for(actor)
    actor.respond_to?(:id) ? actor.id : nil
  rescue
    nil
  end

  private_class_method def self.subject_type_for(subject)
    subject&.class&.name
  end

  private_class_method def self.subject_id_for(subject)
    subject.respond_to?(:id) ? subject.id : nil
  rescue
    nil
  end
end
