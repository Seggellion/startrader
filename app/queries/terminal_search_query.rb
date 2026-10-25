class TerminalSearchQuery
  class InputError < StandardError
    attr_reader :status
    def initialize(message, status)
      super(message)
      @status = status
    end
  end
  LIMIT = 20
  MAX_BYTES = 20 * 1024
  FIELDS = %w[terminals.name terminals.nickname terminals.code terminals.location_name locations.star_system_name locations.planet_name locations.moon_name locations.parent_name].freeze

  def initialize(input)
    raw = input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input.to_h
    raw = raw.stringify_keys
    %w[q star_system].each do |key|
      raise InputError.new("Invalid #{key} parameter", 400) if raw.key?(key) && !raw[key].is_a?(String)
    end
    @query = raw.fetch("q", "").strip
    @system = raw.fetch("star_system", "").strip
    @tokens = @query.split(/\s+/)
    raise InputError.new("Use at most 100 characters and five search words", 422) if @query.length > 100 || @tokens.length > 5 || @system.length > 100
  end

  def call
    return {results: [], has_more: false, state: "Type at least two characters"} if @query.length < 2
    valid_ids = Terminal.where("api_id > 0").group(:api_id).having("COUNT(*) = 1").select(:api_id)
    offers = ProductionFacility.where("production_facilities.id_terminal = terminals.api_id")
      .where.not(commodity_name: [nil, ""]).where.not(location_name: [nil, ""])
      .where("(#{ProductionFacility::PLAYER_CAN_BUY_SQL}) OR (#{ProductionFacility::PLAYER_CAN_SELL_SQL})")
    scope = Terminal.joins(:location).where(api_id: valid_ids).where(offers.arel.exists)
    scope = scope.where(locations: {star_system_name: @system}) if @system.present?
    @tokens.each do |token|
      escaped = "%#{ActiveRecord::Base.sanitize_sql_like(token)}%"
      scope = scope.where(FIELDS.map { |field| "#{field} ILIKE :term" }.join(" OR "), term: escaped)
    end
    prefix = "#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    rank = ActiveRecord::Base.sanitize_sql_array([
      "CASE WHEN LOWER(terminals.name) = LOWER(?) OR LOWER(terminals.code) = LOWER(?) THEN 0 WHEN terminals.name ILIKE ? OR terminals.code ILIKE ? THEN 1 ELSE 2 END",
      @query, @query, prefix, prefix
    ])
    rows = scope.order(Arel.sql(rank), Arel.sql("LOWER(terminals.name) ASC"), :api_id).limit(LIMIT + 1)
      .pluck(:api_id, :name, :code, :nickname, :location_name, "locations.star_system_name", "locations.planet_name", "locations.moon_name", "locations.parent_name")
    response = {
      results: rows.first(LIMIT).map { |id, name, code, nickname, location, system, planet, moon, parent|
        {terminal_api_id: id, name: name, code: code, nickname: nickname, location_name: location,
         star_system_name: system, context: [location, system, planet, moon, parent].compact_blank.uniq.join(" / ")}
      }, has_more: rows.size > LIMIT
    }
    while response.to_json.bytesize > MAX_BYTES && response[:results].any?
      response[:results].pop
      response[:has_more] = true
    end
    response
  end
end
