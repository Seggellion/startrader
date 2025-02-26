class EconomyController < ApplicationController

    def index
        @cities = City.all
        @npcs = Npc.all
        @contributions = PlayerContribution
        .select("player_uuid, player_name, commodity_type, commodity_name, SUM(total_contribution) AS total_contribution, MAX(biggest_single) AS biggest_single")
        .group("player_uuid, player_name, commodity_type, commodity_name")
        .order("total_contribution DESC")
        .limit(10)
  
        render "pages/economy"
  
    end

end