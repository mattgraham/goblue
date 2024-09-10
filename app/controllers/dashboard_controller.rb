class DashboardController < ApplicationController
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  def index
    response = HTTParty.get('https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/michigan/schedule')  
    @games = response['events']
  end
end
