module Api
  class CommoditiesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def index
      facilities = ProductionFacility.trade_available.includes(:commodity).ordered_for_api.to_a
      terminals_by_api_id = terminals_by_api_id_for(facilities)
      locations_by_name = locations_by_name_for(facilities, terminals_by_api_id)

      resources = facilities.filter_map do |facility|
        terminal = terminals_by_api_id[facility.id_terminal]
        location = locations_by_name[facility.location_name.presence || terminal&.location_name]

        next unless facility.trade_available?

        location_label = facility.terminal_display_name(terminal: terminal, location: location)
        next if location_label.blank?

        resource_object(facility, location_label: location_label, terminal: terminal, location: location)
      end

      render json: { data: resources.sort_by { |resource| resource.fetch(:sort_key) }.map { |resource| resource.fetch(:data) } }
    end

    private

    def resource_object(facility, location_label:, terminal:, location:)
      id = facility.commodity_api_id.to_s

      {
        sort_key: facility.api_sort_key(terminal: terminal, location: location),
        data: {
          id: id,
          type: "commodities",
          links: {
            self: "https://ctd.altama.energy/commodities/#{id}"
          },
          attributes: {
            name: facility.commodity_display_name,
            location: location_label,
            sell: facility.purchasable? ? facility.api_buy_price : 0,
            buy: facility.sellable? ? facility.api_sell_price : 0,
            vice: facility.vice?,
            "updated-at": facility.updated_at.iso8601(3),
            "out-of-date": facility.out_of_date?
          }
        }
      }
    end

    def terminals_by_api_id_for(facilities)
      terminal_api_ids = facilities.filter_map(&:id_terminal).uniq
      return {} if terminal_api_ids.empty?

      Terminal.where(api_id: terminal_api_ids).index_by(&:api_id)
    end

    def locations_by_name_for(facilities, terminals_by_api_id)
      location_names = facilities.filter_map(&:location_name)
      location_names.concat(terminals_by_api_id.values.filter_map(&:location_name))
      location_names = location_names.uniq

      return {} if location_names.empty?

      Location.where(name: location_names).index_by(&:name)
    end
  end
end
