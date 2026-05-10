# AccountabilityHelper
#
# Renders the status pill used in the weekly digest email and the
# dashboard. Two rendering modes:
#
#   - Default (email): inline-styled <span> with explicit hex bg/fg —
#     email clients render reliably without external CSS.
#   - Web (web: true): class-based <span class="rogue-badge --variant">
#     with an inlined Heroicon — picks up rogue_components.css styles.
#
# Status → variant mapping mirrors the design system's STATUS_MAP.
module AccountabilityHelper
  STATUS_BADGES = {
    on_time: {label: "On time", bg: "#DCFCE7", fg: "#14532D", variant: :success, icon: :check_circle},
    pending_setup: {label: "Awaiting setup", bg: "#F1F5F9", fg: "#334155", variant: :neutral, icon: :clock},
    pending_first_submission: {
      label: "Pending first submission",
      bg: "#F1F5F9",
      fg: "#334155",
      variant: :neutral,
      icon: :clock
    },
    late: {label: "Late", bg: "#FEF3C7", fg: "#78350F", variant: :warning, icon: :exclamation_tri},
    due_soon: {label: "Due soon", bg: "#FEF3C7", fg: "#78350F", variant: :warning, icon: :exclamation_tri},
    overdue: {label: "Overdue", bg: "#FEE2E2", fg: "#991B1B", variant: :danger, icon: :exclamation_circle},
    fallback_fanout: {label: "Escalated", bg: "#FEE2E2", fg: "#991B1B", variant: :danger, icon: :exclamation_circle},
    gm_nudge: {label: "Escalated to GM", bg: "#FEE2E2", fg: "#991B1B", variant: :danger, icon: :exclamation_circle}
  }.freeze

  # Heroicons (20 viewbox, solid, MIT-licensed) — pulled from the design's Icons.jsx.
  STATUS_ICON_PATHS = {
    check_circle: "M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z",
    clock: "M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .2.08.39.22.53l3 3a.75.75 0 101.06-1.06L10.75 9.69V5z",
    exclamation_tri: "M8.485 2.495a1.75 1.75 0 013.03 0l6.28 10.875A1.75 1.75 0 0116.28 16H3.72a1.75 1.75 0 01-1.515-2.63L8.485 2.495zM10 6a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 6zm0 8a1 1 0 100-2 1 1 0 000 2z",
    exclamation_circle: "M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 10-2 0v4a1 1 0 102 0V6zm-1 8a1 1 0 100-2 1 1 0 000 2z"
  }.freeze

  def status_badge(status, web: false)
    spec = STATUS_BADGES[status.to_sym] ||
      {label: status.to_s.tr("_", " ").capitalize, bg: "#F1F5F9", fg: "#334155", variant: :neutral, icon: nil}

    if web
      render_web_badge(spec)
    else
      render_email_badge(spec)
    end
  end

  private

  def render_email_badge(spec)
    style = "display: inline-block; padding: 2px 10px; border-radius: 999px; " \
      "background: #{spec[:bg]}; color: #{spec[:fg]}; font-size: 12px; font-weight: 600;"
    content_tag(:span, spec[:label], style: style)
  end

  def render_web_badge(spec)
    icon = status_icon_svg(spec[:icon])
    content_tag(:span, class: "rogue-badge --#{spec[:variant]}") do
      safe_join([icon, spec[:label]].compact)
    end
  end

  def status_icon_svg(icon_key)
    return nil if icon_key.nil?
    path = STATUS_ICON_PATHS[icon_key]
    return nil if path.nil?
    content_tag(:svg, viewBox: "0 0 20 20", fill: "currentColor", "aria-hidden": "true") do
      tag.path(d: path, "fill-rule": "evenodd", "clip-rule": "evenodd")
    end
  end
end
