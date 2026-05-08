# AccountabilityHelper
#
# Tiny view helper for rendering status badges in the weekly digest
# email and the placeholder dashboard. Inline-styled so the email
# clients render the colors without needing CSS support.
module AccountabilityHelper
  STATUS_BADGES = {
    on_time:                  { label: "On time",                  bg: "#d4f4dd", fg: "#0f5132" },
    pending_setup:            { label: "Awaiting setup",           bg: "#e8e8e8", fg: "#444" },
    pending_first_submission: { label: "Pending first submission", bg: "#e8e8e8", fg: "#444" },
    late:                     { label: "Late",                     bg: "#ffe9b5", fg: "#7a4f01" },
    overdue:                  { label: "Overdue",                  bg: "#fbd7d7", fg: "#7a1212" }
  }.freeze

  def status_badge(status)
    spec = STATUS_BADGES[status.to_sym] || { label: status.to_s.tr("_", " ").capitalize, bg: "#eee", fg: "#333" }
    style = "display: inline-block; padding: 2px 10px; border-radius: 999px; " \
            "background: #{spec[:bg]}; color: #{spec[:fg]}; font-size: 12px; font-weight: 600;"
    content_tag(:span, spec[:label], style: style)
  end
end
