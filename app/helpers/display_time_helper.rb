# M05: every rendered date/time states its zone. Storage stays UTC; only
# presentation converts. The display zone is the ActiveSupport zone name in
# Setting "admin_display_time_zone" (default UTC), read once per request.
module DisplayTimeHelper
  DEFAULT_TIME_FORMAT = "%Y-%m-%d %H:%M:%S %Z".freeze
  DEFAULT_DATE_FORMAT = "%Y-%m-%d %Z".freeze

  def display_time_zone
    @display_time_zone ||= begin
      name = Setting.get("admin_display_time_zone").presence
      (name && ActiveSupport::TimeZone[name]) || ActiveSupport::TimeZone["UTC"]
    end
  end

  def display_time(time, format: DEFAULT_TIME_FORMAT, missing: "Not recorded")
    return missing if time.blank?

    time.in_time_zone(display_time_zone).strftime(format)
  end

  def display_date(time, missing: "Not recorded")
    display_time(time, format: DEFAULT_DATE_FORMAT, missing: missing)
  end
end
