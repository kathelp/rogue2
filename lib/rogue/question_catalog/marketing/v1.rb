module Rogue
  module QuestionCatalog
    module Marketing
      module V1
        VERSION = 1
        DOMAIN = "marketing"

        QUESTIONS = [
          {
            key: "marketing_strategy",
            position: 1,
            prompt: "Who controls your marketing strategy at <%= dealership_name %>?",
            default_cadence: "monthly",
            metrics: [
              { key: "strategy_summary", cadence: "monthly" }
            ]
          },
          {
            key: "marketing_invoices",
            position: 2,
            prompt: "Who is responsible for reviewing and approving marketing invoices at <%= dealership_name %>?",
            default_cadence: "monthly",
            metrics: [
              { key: "invoice_review", cadence: "monthly" }
            ]
          },
          {
            key: "dealer_website",
            position: 3,
            prompt: "Who manages your dealer website at <%= dealership_name %>?",
            default_cadence: "monthly",
            metrics: [
              { key: "website_traffic", cadence: "monthly" },
              { key: "website_leads", cadence: "monthly" }
            ]
          },
          {
            key: "paid_search_social",
            position: 4,
            prompt: "Who manages your paid search and social advertising at <%= dealership_name %>?",
            default_cadence: "monthly",
            metrics: [
              { key: "paid_search_spend", cadence: "monthly" },
              { key: "paid_search_leads", cadence: "monthly" },
              { key: "social_spend", cadence: "monthly" }
            ]
          },
          {
            key: "oem_compliance",
            position: 5,
            prompt: "Who oversees OEM marketing compliance and co-op programs at <%= dealership_name %>?",
            default_cadence: "quarterly",
            metrics: [
              { key: "oem_compliance_status", cadence: "quarterly" }
            ]
          },
          {
            key: "lead_source_attribution",
            position: 6,
            prompt: "Who is responsible for tracking and attributing lead sources at <%= dealership_name %>?",
            default_cadence: "monthly",
            metrics: [
              { key: "lead_source_report", cadence: "monthly" }
            ]
          }
        ].freeze

        # Materialize catalog questions as TenantQuestion rows for a Tenant.
        # Idempotent: skips already-materialized keys for this tenant + version.
        # Substitutes <%= dealership_name %> with the tenant's actual name.
        def self.materialize_for(tenant:)
          QUESTIONS.map do |question_attrs|
            rendered_prompt = question_attrs[:prompt].gsub(
              "<%= dealership_name %>",
              tenant.dealership_name
            )

            TenantQuestion.find_or_create_by!(
              tenant: tenant,
              key: question_attrs[:key],
              catalog_version: VERSION
            ) do |tq|
              tq.domain = DOMAIN
              tq.position = question_attrs[:position]
              tq.prompt = rendered_prompt
              tq.default_cadence = question_attrs[:default_cadence]
              tq.status = :pending
            end
          end
        end
      end
    end
  end
end
