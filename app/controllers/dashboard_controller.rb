class DashboardController < ApplicationController
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :team

  def index
    start_time = Time.current

    # Cache the entire dashboard data for 5 minutes
    @dashboard_data = Rails.cache.fetch("dashboard_data", expires_in: 5.minutes) do
      fetch_dashboard_data
    end

    @games = @dashboard_data[:games]
    @fetch_rankings = @dashboard_data[:rankings]
    @teams_cache = @dashboard_data[:teams_cache]
    @team_records = @dashboard_data[:team_records]
    @conference_standings = @dashboard_data[:conference_standings]
    @scoreboard = @dashboard_data[:scoreboard]

    load_time = Time.current - start_time
    Rails.logger.info "Dashboard loaded in #{load_time.round(2)} seconds"
    Rails.logger.info "Fetch rankings result: #{@fetch_rankings.inspect}"
  end

  private

  def fetch_dashboard_data
    # Fetch games data with timeout
    response = HTTParty.get(
      "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/Michigan/schedule?season=2025&seasontype=2",
      timeout: 10
    )
    data = JSON.parse(response.body)

    # Extract events from the ESPN API response
    events = data["events"] || []

    games = events.map do |event|
      game = {
        "id" => event["id"],
        "name" => event["name"],
        "shortName" => event["shortName"],
        "week" => event.dig("week", "text"),
        "season" => event.dig("season", "displayName"),
        "seasonType" => event.dig("seasonType", "name")
      }

      # Handle date/time from ESPN API
      if event["date"].present?
        # Parse the UTC time and convert to EST
        utc_time = DateTime.parse(event["date"])
        est_time = utc_time.in_time_zone("Eastern Time (US & Canada)")
        game["startDate"] = est_time
        game["date"] = event["date"]
      end

      # Extract competition details
      if event["competitions"]&.first
        competition = event["competitions"].first

        # Extract venue information
        if competition["venue"]
          game["venue"] = {
            "name" => competition["venue"]["fullName"],
            "city" => competition["venue"]["address"]["city"],
            "state" => competition["venue"]["address"]["state"]
          }
          # Set venue string for compatibility with the view
          game["venue"] = "#{competition["venue"]["fullName"]}, #{competition["venue"]["address"]["city"]}, #{competition["venue"]["address"]["state"]}"
        end

        # Extract team information
        if competition["competitors"]
          game["competitors"] = competition["competitors"].map do |competitor|
            {
              "id" => competitor["team"]["id"],
              "name" => competitor["team"]["displayName"],
              "abbreviation" => competitor["team"]["abbreviation"],
              "homeAway" => competitor["homeAway"],
              "logo" => competitor["team"]["logos"]&.first&.dig("href")
            }
          end

          # Set homeId and awayId for compatibility with the view
          home_competitor = competition["competitors"].find { |c| c["homeAway"] == "home" }
          away_competitor = competition["competitors"].find { |c| c["homeAway"] == "away" }

          game["homeId"] = home_competitor["team"]["id"] if home_competitor
          game["awayId"] = away_competitor["team"]["id"] if away_competitor
        end

        # Extract broadcast information
        if competition["broadcasts"]&.first
          game["broadcast"] = {
            "type" => competition["broadcasts"].first["type"]["shortName"],
            "media" => competition["broadcasts"].first["media"]["shortName"]
          }
        end

        # Extract status information
        if competition["status"]
          game["status"] = {
            "type" => competition["status"]["type"]["name"],
            "description" => competition["status"]["type"]["description"],
            "detail" => competition["status"]["type"]["detail"]
          }
        end
      end

      game
    end

    # Fetch rankings
    rankings = fetch_rankings

    # Fetch team records and conference standings
    team_records = fetch_team_records

    # Fetch scoreboard
    scoreboard = fetch_scoreboard

    # Build teams cache to avoid N+1 queries
    teams_cache = build_teams_cache(games, rankings, scoreboard)

    {
      games: games,
      rankings: rankings,
      teams_cache: teams_cache,
      team_records: team_records,
      scoreboard: scoreboard
    }
  end

  def build_teams_cache(games, rankings, scoreboard = [])
    # Collect all unique team IDs
    team_ids = Set.new

    # Add team IDs from games
    games.each do |game|
      team_ids.add(game["homeId"]) if game["homeId"]
      team_ids.add(game["awayId"]) if game["awayId"]
    end

    # Add team IDs from rankings
    rankings.keys.each { |team_id| team_ids.add(team_id) }

    # Add team IDs from scoreboard
    scoreboard.each do |game|
      team_ids.add(game["homeId"]) if game["homeId"]
      team_ids.add(game["awayId"]) if game["awayId"]
    end

    # Fetch all teams data in parallel (if possible) or batch
    teams_cache = {}
    team_ids.each do |team_id|
      teams_cache[team_id] = fetch_team_data(team_id)
    end

    teams_cache
  end

  def fetch_team_data(team_id)
    # Cache individual team data for 1 hour
    Rails.cache.fetch("team_data_#{team_id}", expires_in: 1.hour) do
      response = HTTParty.get(
        "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/#{team_id}",
        timeout: 5
      )
      data = JSON.parse(response.body)
      team_data = data["team"]

      # Handle case where team_data might be nil
      return { logo: nil, name: "Unknown Team", color: nil, abbreviation: nil } unless team_data

      {
        logo: team_data.dig("logos", 0, "href"),
        name: team_data["displayName"],
        color: team_data["color"],
        abbreviation: team_data["abbreviation"]
      }
    end
  end

  def fetch_rankings
    # Cache rankings for 30 minutes
    Rails.cache.fetch("ap_rankings", expires_in: 30.minutes) do
      begin
        Rails.logger.info "Fetching AP Top 25 rankings from ESPN API..."
        response = HTTParty.get(
          "http://site.api.espn.com/apis/site/v2/sports/football/college-football/rankings?week=1&seasonType=2&rankings=1",
          timeout: 10
        )
        Rails.logger.info "Response status: #{response.code}"
        Rails.logger.info "Response body length: #{response.body.length}"

        data = JSON.parse(response.body)
        Rails.logger.info "Parsed data keys: #{data.keys}"

        # Debug available rankings
        if data["rankings"]
          Rails.logger.info "Available rankings: #{data['rankings'].map { |r| r['name'] }}"
        end

        # Extract AP Top 25 rankings (ID 1)
        rankings_data = []

        if data["rankings"]
          ap_ranking = data["rankings"].find { |ranking| ranking["id"] == "1" }
          if ap_ranking
            rankings_data = ap_ranking["ranks"] || []
            Rails.logger.info "Found AP Top 25 rankings with #{rankings_data.length} teams"
          else
            Rails.logger.info "AP Top 25 rankings not found"
          end
        end
        Rails.logger.info "Rankings data found: #{rankings_data.length} entries"

        # Create a hash mapping team IDs to their current and previous rankings
        rankings_hash = {}
        rankings_data.each do |rank|
          team_id = rank.dig("team", "id")
          current_rank = rank["current"]
          previous_rank = rank["previous"]
          if team_id && current_rank && current_rank > 0
            rankings_hash[team_id] = {
              current: current_rank,
              previous: previous_rank
            }
          end
        end

        Rails.logger.info "Final rankings hash: #{rankings_hash}"
        rankings_hash
      rescue => e
        Rails.logger.error "Failed to fetch rankings: #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(5)}"
        # Return empty hash if rankings fetch fails
        {}
      end
    end
  end

  def fetch_team_records
    # Cache team records for 30 minutes
    Rails.cache.fetch("team_records", expires_in: 30.minutes) do
      begin
        Rails.logger.info "Fetching team records from ESPN API..."

        # Fetch Michigan's team data which includes record and standingSummary
        response = HTTParty.get(
          "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/130",
          timeout: 10
        )
        data = JSON.parse(response.body)
        team_data = data["team"]

                if team_data
          # Handle the record structure which has an 'items' array
          records = team_data["record"]&.dig("items") || []
          overall_record = records.find { |r| r["type"] == "total" }
          conference_record = records.find { |r| r["type"] == "conference" }

          # Extract standing summary
          standing_summary = team_data["standingSummary"] || "N/A"

          # Extract detailed record stats
          record_stats = {}
          if overall_record && overall_record["stats"]
            overall_record["stats"].each do |stat|
              record_stats[stat["name"]] = stat["value"]
            end
          end

          {
            "130" => {
              overall: overall_record ? "#{overall_record['wins']}-#{overall_record['losses']}" : "N/A",
              conference: conference_record ? "#{conference_record['wins']}-#{conference_record['losses']}" : "N/A",
              standing_summary: standing_summary,
              record_stats: record_stats,
              summary: overall_record ? overall_record["summary"] : "N/A"
            }
          }
                else
          { "130" => { overall: "N/A", conference: "N/A", standing_summary: "N/A", record_stats: {}, summary: "N/A" } }
                end
      rescue => e
        Rails.logger.error "Failed to fetch team records: #{e.message}"
        { "130" => { overall: "N/A", conference: "N/A", standing_summary: "N/A", record_stats: {}, summary: "N/A" } }
      end
    end
  end

  def fetch_scoreboard
    # Cache scoreboard for 5 minutes
    Rails.cache.fetch("scoreboard", expires_in: 5.minutes) do
      begin
        Rails.logger.info "Fetching scoreboard from ESPN API..."
        response = HTTParty.get(
          "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard",
          timeout: 10
        )
        Rails.logger.info "Scoreboard response status: #{response.code}"
        Rails.logger.info "Scoreboard response body length: #{response.body.length}"

        data = JSON.parse(response.body)
        Rails.logger.info "Scoreboard data keys: #{data.keys}"

        events = data["events"] || []
        Rails.logger.info "Found #{events.length} events in scoreboard"

        # Filter for games with ranked teams (top 25 only)
        ranked_games = events.select do |event|
          if event["competitions"]&.first&.dig("competitors")
            competitors = event["competitions"].first["competitors"]
            # Check if any competitor is ranked in the top 25 using curatedRank.current
            competitors.any? do |competitor|
              curated_rank = competitor.dig("curatedRank", "current")
              # Team is ranked if curatedRank.current exists and is between 1 and 25
              curated_rank && curated_rank > 0 && curated_rank <= 25
            end
          else
            false
          end
        end

        Rails.logger.info "Found #{ranked_games.length} games with potential ranked teams"

        # Transform the data to match our expected format
        transformed_games = ranked_games.map do |event|
          game = {
            "id" => event["id"],
            "name" => event["name"],
            "shortName" => event["shortName"],
            "week" => event.dig("week", "text"),
            "season" => event.dig("season", "displayName"),
            "seasonType" => event.dig("seasonType", "name")
          }

          # Handle date/time from ESPN API
          if event["date"].present?
            utc_time = DateTime.parse(event["date"])
            est_time = utc_time.in_time_zone("Eastern Time (US & Canada)")
            game["startDate"] = est_time
            game["date"] = event["date"]
          end

          # Extract competition details
          if event["competitions"]&.first
            competition = event["competitions"].first

            # Extract venue information
            if competition["venue"] && competition["venue"]["address"]
              venue = competition["venue"]
              address = venue["address"]
              if venue["fullName"] && address["city"] && address["state"]
                game["venue"] = "#{venue["fullName"]}, #{address["city"]}, #{address["state"]}"
              end
            end

            # Extract team information
            if competition["competitors"]
              game["competitors"] = competition["competitors"].map do |competitor|
                if competitor["team"]
                  {
                    "id" => competitor["team"]["id"],
                    "name" => competitor["team"]["displayName"],
                    "abbreviation" => competitor["team"]["abbreviation"],
                    "homeAway" => competitor["homeAway"],
                    "logo" => competitor["team"]["logos"]&.first&.dig("href"),
                    "curatedRank" => competitor["curatedRank"]
                  }
                else
                  nil
                end
              end.compact

              # Set homeId and awayId for compatibility with the view
              home_competitor = competition["competitors"].find { |c| c["homeAway"] == "home" && c["team"] }
              away_competitor = competition["competitors"].find { |c| c["homeAway"] == "away" && c["team"] }

              game["homeId"] = home_competitor["team"]["id"] if home_competitor
              game["awayId"] = away_competitor["team"]["id"] if away_competitor
            end

            # Extract broadcast information
            if competition["broadcasts"]&.first
              broadcast = competition["broadcasts"].first
              if broadcast["names"] && broadcast["names"].any?
                game["broadcast"] = {
                  "media" => broadcast["names"].join(", ")
                }
              end
            end

            # Extract status information
            if competition["status"]
              game["status"] = {
                "type" => competition["status"]["type"]["name"],
                "description" => competition["status"]["type"]["description"],
                "detail" => competition["status"]["type"]["detail"],
                "period" => competition["status"]["period"],
                "clock" => competition["status"]["clock"],
                "displayClock" => competition["status"]["displayClock"]
              }
            end

            # Extract scores
            if competition["competitors"]
              game["scores"] = {}
              competition["competitors"].each do |competitor|
                if competitor["team"] && competitor["score"]
                  team_id = competitor["team"]["id"]
                  game["scores"][team_id] = {
                    "score" => competitor["score"],
                    "homeAway" => competitor["homeAway"]
                  }
                end
              end
            end
          end

                    game
        end



        Rails.logger.info "Final scoreboard result: #{transformed_games.length} games"
        transformed_games
      rescue => e
        Rails.logger.error "Failed to fetch scoreboard: #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(5)}"
        []
      end
    end
  end



  def team(team_id)
    # Use the cached teams data instead of making API calls
    @teams_cache[team_id] || fetch_team_data(team_id)
  end
end
