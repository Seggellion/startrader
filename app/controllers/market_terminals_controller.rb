class MarketTerminalsController < ApplicationController
  def index
    render json: TerminalSearchQuery.new(params).call
  rescue TerminalSearchQuery::InputError => error
    render json: {error: error.message, results: [], has_more: false}, status: error.status
  end
end
