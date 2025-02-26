# app/controllers/leaderboard_controller.rb
class LeaderboardController < ApplicationController
    def index
      # This is just an example. The final logic depends on how you want to group/rank players:
      @contributions = PlayerContribution
                         .select("player_uuid, commodity_type, commodity_name, SUM(total_contribution) AS total_contribution, MAX(biggest_single) AS biggest_single")
                         .group("player_uuid, commodity_type, commodity_name")
                         .order("total_contribution DESC")
                         .limit(10)
    end
  end
  