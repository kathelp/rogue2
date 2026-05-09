class Vendor < ApplicationRecord
  # --------------------------------------------------------------------------
  # Enums
  # --------------------------------------------------------------------------
  enum(
    :state,
    {
      active: "active",
      pending_review: "pending_review",
      archived: "archived"
    },
    prefix: :state
  )

  enum(
    :source,
    {
      seed: "seed",
      clarification: "clarification",
      manual: "manual"
    },
    prefix: :source
  )

  # --------------------------------------------------------------------------
  # Associations
  # --------------------------------------------------------------------------
  belongs_to :parent_vendor, class_name: "Vendor", optional: true
  belongs_to :created_by_tenant, class_name: "Tenant", optional: true

  has_many(
    :sub_vendors,
    class_name: "Vendor",
    foreign_key: :parent_vendor_id,
    dependent: :nullify,
    inverse_of: :parent_vendor
  )
  has_many :contacts, dependent: :nullify

  # --------------------------------------------------------------------------
  # Validations
  # --------------------------------------------------------------------------
  validates :name, presence: true
  validates :state, presence: true, inclusion: {in: states.keys}
  validates :source, presence: true, inclusion: {in: sources.keys}

  # --------------------------------------------------------------------------
  # Scopes
  # --------------------------------------------------------------------------
  # Returns vendors whose domains array contains the lowercased input domain.
  scope(
    :matching_domain,
    -> (domain_str) {
      where("? = ANY(domains)", domain_str.to_s.downcase.strip)
    }
  )

  scope :active_vendors, -> { where(state: :active) }

  # --------------------------------------------------------------------------
  # Class methods
  # --------------------------------------------------------------------------
  # Shared write path for seed loader and runtime clarifier.
  def self.bootstrap!(name:, domains: [], source: :seed, state: :active, **attrs)
    find_or_initialize_by(name: name).tap do |vendor|
      vendor.assign_attributes(
        domains: Array(domains).map { |d| d.downcase.strip },
        source: source,
        state: state,
        **attrs
      )
      vendor.save!
    end
  end
end
