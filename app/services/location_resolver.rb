# app/services/location_resolver.rb
class LocationResolver
  FACILITY_SUFFIXES = [
    "tdd",
    "trade development division",
    "trade and development division",
    "trade terminal",
    "trading terminal",
    "commodity terminal",
    "commodities terminal",
    "admin",
    "administration",
    "spaceport",
    "space port",
    "hangar",
    "hangars",
    "cargo center",
    "cargo centre",
    "freight elevator"
  ].freeze

  NOISE_TOKENS = %w[
    tdd
    trade
    trading
    development
    division
    terminal
    terminals
    commodity
    commodities
    admin
    administration
    spaceport
    space
    port
    hangar
    hangars
    cargo
    freight
    elevator
    center
    centre
  ].freeze

  MIN_SCORE = 80
  MIN_CODE_QUERY_LENGTH = 5
  MIN_TOKEN_MATCH_COUNT = 2
  MIN_ALPHA_TOKEN_LENGTH = 3

  def self.resolve(name)
    new(name).resolve
  end

  def initialize(name)
    @raw_name = name.to_s
  end

  def resolve
    return nil if @raw_name.blank?

    exact = exact_match
    return exact if exact

    ranked_match
  end

  private

  def exact_match
    queries = variants.map { |variant| compact(variant) }.uniq

    Location
      .where(
        <<~SQL.squish,
          regexp_replace(lower(coalesce(name, '')), '[^a-z0-9]+', '', 'g') IN (:queries)
          OR regexp_replace(lower(coalesce(nickname, '')), '[^a-z0-9]+', '', 'g') IN (:queries)
          OR regexp_replace(lower(coalesce(code, '')), '[^a-z0-9]+', '', 'g') IN (:queries)
        SQL
        queries:
      )
      .first
  end

  def ranked_match
    query_variants = variants
    query_tokens = query_variants.flat_map { |variant| words(variant) }.uniq
    meaningful_query_tokens = query_tokens - NOISE_TOKENS

    return nil if meaningful_query_tokens.empty?

    best = nil

    Location.find_each do |location|
      score = score_location(location, meaningful_query_tokens, query_variants)

      next if score < MIN_SCORE
      # Equal scores keep Location.find_each's deterministic primary-key order.
      next if best && score <= best[:score]

      best = {
        score: score,
        location: location
      }
    end

    best&.fetch(:location)
  end

  def score_location(location, meaningful_query_tokens, query_variants)
    score = 0

    location_names = [
      location.name,
      location.nickname,
      location.code
    ].compact_blank

    location_names.each do |location_name|
      location_words = words(location_name)
      location_compact = compact(location_name)

      query_variants.each do |query_variant|
        query_compact = compact(query_variant)

        if query_compact == location_compact
          score = [score, 100].max
        elsif significant_code_query?(query_compact) && location_compact.include?(query_compact)
          score = [score, 92].max
        elsif query_compact.start_with?(location_compact)
          leftover = query_compact.delete_prefix(location_compact)

          if leftover.present?
            score = [score, 90].max
          end
        end
      end

      if location_words.present? && (location_words - meaningful_query_tokens).empty?
        score = [score, 85].max
      end
    end

    if safe_token_match?(meaningful_query_tokens, query_variants, location_names)
      score = [score, token_match_score(meaningful_query_tokens, query_variants)].max
    end

    if mentions_trade_terminal? && location.has_trade_terminal?
      score += 5
    end

    if location.parent_name.present? && meaningful_query_tokens.include?(normalize(location.parent_name))
      score += 3
    end

    if location.planet_name.present? && meaningful_query_tokens.include?(normalize(location.planet_name))
      score += 3
    end

    score
  end

  def safe_token_match?(meaningful_query_tokens, query_variants, location_names)
    return false unless token_match_candidate?(meaningful_query_tokens, query_variants)

    location_tokens = searchable_tokens(location_names)

    (meaningful_query_tokens - location_tokens).empty?
  end

  def token_match_candidate?(meaningful_query_tokens, query_variants)
    return true if query_variants.any? { |variant| significant_code_query?(compact(variant)) }
    return false if meaningful_query_tokens.length < MIN_TOKEN_MATCH_COUNT

    meaningful_query_tokens.any? { |token| significant_alpha_token?(token) }
  end

  def token_match_score(meaningful_query_tokens, query_variants)
    return 91 if query_variants.any? { |variant| significant_code_query?(compact(variant)) }

    numeric_token_count = meaningful_query_tokens.count { |token| token.match?(/\A\d+\z/) }
    88 + [numeric_token_count, 2].min
  end

  def searchable_tokens(values)
    values.flat_map { |value| derived_tokens(value) }.uniq
  end

  def derived_tokens(value)
    tokens = words(value)

    (
      tokens +
      tokens.flat_map { |token| split_alpha_numeric_token(token) } +
      code_sequence_tokens(tokens)
    ).uniq
  end

  def split_alpha_numeric_token(token)
    return [] unless token.match?(/[a-z]/) && token.match?(/\d/)

    token.scan(/[a-z]+|\d+/)
  end

  def code_sequence_tokens(tokens)
    tokens.each_cons(2).filter_map do |left, right|
      joined = "#{left}#{right}"
      joined if significant_code_query?(joined)
    end
  end

  def significant_code_query?(value)
    value.length >= MIN_CODE_QUERY_LENGTH &&
      value.match?(/[a-z]/) &&
      value.match?(/\d/)
  end

  def significant_alpha_token?(token)
    token.match?(/[a-z]/) &&
      token.gsub(/[^a-z]/, "").length >= MIN_ALPHA_TOKEN_LENGTH
  end

  def variants
    base = normalize(@raw_name)

    [
      base,
      strip_trailing_facility_suffix(base),
      remove_noise_tokens(base)
    ].compact_blank.uniq
  end

  def strip_trailing_facility_suffix(value)
    result = value.dup

    FACILITY_SUFFIXES.each do |suffix|
      result = result.sub(/\s+#{Regexp.escape(suffix)}\z/, "")
    end

    result.squish
  end

  def remove_noise_tokens(value)
    tokens = words(value) - NOISE_TOKENS
    tokens.join(" ")
  end

  def mentions_trade_terminal?
    words(@raw_name).intersect?(%w[tdd terminal trade trading commodity commodities])
  end

  def words(value)
    normalize(value).split
  end

  def compact(value)
    normalize(value).delete(" ")
  end

  def normalize(value)
    ActiveSupport::Inflector
      .transliterate(value.to_s)
      .downcase
      .gsub("&", " and ")
      .gsub(/[^a-z0-9]+/, " ")
      .squish
  end
end
