# OnboardingFlow::RequestProvisioning
#
# Creates Request rows on a Source from the question catalog's metric list.
# Idempotent on (source, metric_key).
#
# Usage:
#   OnboardingFlow::RequestProvisioning.call(
#     source:          source,
#     tenant_question: question
#   )
module OnboardingFlow
  module RequestProvisioning
    def self.call(source:, tenant_question:)
      metrics = Rogue::QuestionCatalog::Marketing::V1.metrics_for(key: tenant_question.key)
      return [] if metrics.empty?

      metrics.map do |metric|
        Request.find_or_create_by!(
          tenant:     source.tenant,
          source:     source,
          metric_key: metric[:key]
        ) do |r|
          r.cadence = metric[:cadence]
        end
      end
    end
  end
end
