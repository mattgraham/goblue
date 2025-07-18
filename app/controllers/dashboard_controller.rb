class DashboardController < ApplicationController
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :team

  def index
    response = HTTParty.get("https://apinext.collegefootballdata.com/games?year=2025&team=Michigan",
      headers: { "Authorization" => "Bearer 15AqBDGCRX6xgFTZ8JhWZEv2zPEDIl9EUmxk4gH4AX5TQXBSRanN9QOSd5E9OXDT" })
    games_data = JSON.parse(response.body)
    @games_data = games_data

    @games = games_data.map do |game|
      if game["startDate"].present?
        # Parse the UTC time and convert to EST
        utc_time = DateTime.parse(game["startDate"])
        est_time = utc_time.in_time_zone("Eastern Time (US & Canada)")
        game["startDate"] = est_time
      end
      game
    end
  end


  def team(team_id)
    response = HTTParty.get("https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/#{team_id}")
    data = JSON.parse(response.body)
    team_data = data["team"]
    {
      logo: team_data.dig("logos", 0, "href"),
      name: team_data["displayName"],
      color: team_data["color"],
      abbreviation: team_data["abbreviation"]
    }
  end
end
