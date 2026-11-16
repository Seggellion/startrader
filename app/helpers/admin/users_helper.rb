module Admin
  module UsersHelper
    COMPARISON_LABELS = {
      aligned: ["Aligned", "border-emerald-200 bg-emerald-50 text-emerald-700"],
      diverged: ["Diverged", "border-rose-200 bg-rose-50 text-rose-700"],
      unknown: ["Unknown", "border-amber-200 bg-amber-50 text-amber-700"],
      in_transit: ["In transit", "border-sky-200 bg-sky-50 text-sky-700"],
      interdicted: ["Interdicted", "border-amber-200 bg-amber-50 text-amber-800"]
    }.freeze

    # Explicit UTC with zone label. Missing values are labelled, never blank.
    def admin_utc(time, missing: "Not recorded")
      time.present? ? time.utc.strftime("%Y-%m-%d %H:%M:%S UTC") : missing
    end

    def comparison_badge(status)
      label, classes = COMPARISON_LABELS.fetch(status)
      content_tag(:span, label, class: "inline-flex rounded-full border px-2 py-0.5 text-xs font-semibold #{classes}")
    end

    def ship_status_badge(status)
      classes =
        case status.to_s
        when "in_transit" then "border-sky-200 bg-sky-50 text-sky-700"
        when "docked", "landed", "in orbit", "available" then "border-emerald-200 bg-emerald-50 text-emerald-700"
        when "interdicted" then "border-amber-200 bg-amber-50 text-amber-700"
        when "destroyed", "disabled" then "border-rose-200 bg-rose-50 text-rose-700"
        else "border-slate-200 bg-slate-50 text-slate-700"
        end
      content_tag(:span, status.presence || "Unknown", class: "inline-flex rounded-full border px-2 py-0.5 text-xs font-semibold #{classes}")
    end

    # Local avatar: initials only, so no identifier leaves the server.
    def admin_initials(user)
      source = user.username.presence || "User #{user.id}"
      source.scan(/[A-Za-z0-9]+/).first(2).map { |part| part[0] }.join.upcase.presence || "?"
    end

    def admin_credits(amount)
      return "Not recorded" if amount.nil?
      "#{number_with_delimiter(amount.to_d.round(0).to_i)} aUEC"
    end

    def admin_pretty_json(value)
      JSON.pretty_generate(value)
    rescue JSON::GeneratorError, TypeError
      value.inspect
    end
  end
end
