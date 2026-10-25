# The public market is player-facing. id_terminal is an external UEX identity.
class MarketQuery
  PER_PAGE = 50
  FILTER_KEYS = %w[q star_system commodity_id location_type trade_mode sort direction terminal_api_id page buy_page sell_page].freeze
  Page = Struct.new(:rows, :total_count, :page, :total_pages, :source_modified_at, keyword_init: true) do
    def previous_page = page > 1 ? page - 1 : nil
    def next_page = page < total_pages ? page + 1 : nil
  end
  Result = Struct.new(:filters, :terminal, :selection_error, :warning, :buy, :sell, :legacy, :generated_at, keyword_init: true) do
    def grouped? = filters.key?(:terminal_api_id)
    def rows = grouped? ? (buy.rows + sell.rows).uniq(&:id) : legacy.rows
    def source_modified_at = [buy&.source_modified_at, sell&.source_modified_at, legacy&.source_modified_at].compact.max
  end

  def initialize(input = {})
    raw = input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input.to_h
    raw = raw.stringify_keys.slice(*FILTER_KEYS)
    @invalid_terminal_shape = raw.key?("terminal_api_id") && !raw["terminal_api_id"].is_a?(String) && !raw["terminal_api_id"].is_a?(Integer) && !raw["terminal_api_id"].nil?
    @filters = raw.each_with_object({}) do |(key, value), out|
      out[key.to_sym] = value.to_s if (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.present?
    end
    @filters[:terminal_api_id] = "invalid" if @invalid_terminal_shape
    @filters[:trade_mode] = "" unless %w[buy sell both].include?(@filters[:trade_mode])
    @filters[:sort] = "updated" unless sort_columns.key?(@filters[:sort])
    @filters[:direction] = @filters[:direction] == "asc" ? "asc" : "desc"
    @filters.delete_if { |_, value| value == "" }
  end

  def call
    # Avoid isolating an already-open test/caller transaction. In ordinary GETs,
    # materialize all counts/rows/preloads within one read-only snapshot.
    if ActiveRecord::Base.connection.transaction_open?
      load_result
    else
      ActiveRecord::Base.transaction(isolation: :repeatable_read) do
        ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
        load_result
      end
    end
  end

  def self.terminal_identity(value)
    string = value.to_s
    return unless /\A[1-9][0-9]{0,9}\z/.match?(string)
    number = string.to_i
    number if number <= 2_147_483_647
  end

  private

  def load_result
    terminal = nil
    error = nil
    warning = nil
    grouped = @filters.key?(:terminal_api_id)
    if grouped
      id = self.class.terminal_identity(@filters[:terminal_api_id])
      candidates = id ? Terminal.where(api_id: id).includes(:location).limit(2).to_a : []
      terminal = candidates.first if candidates.size == 1
      error = "This terminal selection is invalid or unavailable. Clear it and select a terminal again." unless terminal&.location
      if !error && @filters[:star_system].present? && terminal.location.star_system_name != @filters[:star_system]
        warning = "The selected terminal is outside the selected star system. Clear the system or choose a compatible terminal."
      end
    end
    scope = common_scope
    scope = error ? scope.none : scope.where(id_terminal: terminal.api_id) if grouped
    result = Result.new(filters: @filters.dup, terminal: terminal, selection_error: error, warning: warning, generated_at: Time.current)
    if grouped
      @filters.delete(:page)
      result.buy = load_page(scope.player_can_buy, :buy_page)
      result.sell = load_page(scope.player_can_sell, :sell_page)
    else
      @filters.delete(:buy_page)
      @filters.delete(:sell_page)
      result.legacy = load_page(scope, :page)
    end
    result.filters = @filters.dup
    ActiveRecord::Associations::Preloader.new(records: result.rows, associations: [:commodity, :location]).call
    result
  end

  def common_scope
    scope = ProductionFacility.left_joins(:location)
      .where.not(commodity_name: [nil, ""]).where.not(location_name: [nil, ""])
    if @filters[:q].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@filters[:q])}%"
      scope = scope.where(
        "production_facilities.facility_name ILIKE :term OR production_facilities.location_name ILIKE :term OR production_facilities.commodity_name ILIKE :term OR locations.parent_name ILIKE :term OR locations.star_system_name ILIKE :term OR locations.planet_name ILIKE :term OR locations.moon_name ILIKE :term",
        term: term
      )
    end
    scope = scope.where(locations: {star_system_name: @filters[:star_system]}) if @filters[:star_system].present?
    scope = scope.where(commodity_name: Commodity.where(id: @filters[:commodity_id]).select(:name)) if @filters[:commodity_id].present?
    scope = scope.where(locations: {classification: @filters[:location_type]}) if @filters[:location_type].present?
    case @filters[:trade_mode]
    when "buy" then scope.player_can_buy
    when "sell" then scope.player_can_sell
    when "both" then scope.player_can_buy.player_can_sell
    else scope
    end
  end

  def load_page(scope, key)
    count, source_time = scope.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(production_facilities.date_modified)"))
    count = count.to_i
    total_pages = (count.to_f / PER_PAGE).ceil
    requested = @filters[key].to_s
    number = /\A[1-9][0-9]{0,8}\z/.match?(requested) ? requested.to_i : 1
    number = [number, [total_pages, 1].max].min
    @filters[key] = number.to_s
    rows = scope.order(Arel.sql("#{sort_columns.fetch(@filters[:sort])} #{@filters[:direction].upcase} NULLS LAST"), id: :asc)
      .offset((number - 1) * PER_PAGE).limit(PER_PAGE).to_a
    Page.new(rows: rows, total_count: count, page: number, total_pages: total_pages, source_modified_at: source_time)
  end

  def quote_sql(side)
    support = side == "buy" ? ProductionFacility::PLAYER_CAN_BUY_SQL : ProductionFacility::PLAYER_CAN_SELL_SQL
    local = "production_facilities.local_#{side}_price"
    imported = "production_facilities.price_#{side}"
    active = "(CASE WHEN #{local} > 0 THEN #{local} ELSE COALESCE(#{imported}, 0) END)"
    "(CASE WHEN (#{support}) AND #{active} > 0 THEN #{active} ELSE NULL END)"
  end

  def sort_columns
    {
      "location" => "production_facilities.location_name",
      "commodity" => "production_facilities.commodity_name",
      "buy_price" => quote_sql("buy"),
      "sell_price" => quote_sql("sell"),
      "inventory" => "production_facilities.inventory",
      "demand" => "production_facilities.scu_buy",
      "profit_margin" => "(#{quote_sql('sell')} - #{quote_sql('buy')})",
      "updated" => "production_facilities.updated_at"
    }
  end
end
