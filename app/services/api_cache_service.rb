class ApiCacheService
  CACHE_DIR = Rails.root.join("tmp", "api_cache")

  # API endpoints that need to be cached
  ENDPOINTS = {
    michigan_schedule: "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/Michigan/schedule?season=2025&seasontype=2",
    current_week: "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard",
    ap_rankings: "http://site.api.espn.com/apis/site/v2/sports/football/college-football/rankings?week=1&seasonType=2&rankings=1",
    michigan_team: "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/130",
    scoreboard: "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard"
  }

  def self.initialize_cache_directory
    FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)
  end

  def self.cache_file_path(endpoint_name)
    CACHE_DIR.join("#{endpoint_name}.json")
  end

  def self.fetch_and_cache_all_data
    initialize_cache_directory
    results = {}

    ENDPOINTS.each do |name, url|
      Rails.logger.info "Fetching and caching #{name} from #{url}"

      begin
        response = HTTParty.get(url, timeout: 10)

        if response.success?
          data = JSON.parse(response.body)
          cache_file = cache_file_path(name)

          # Write to cache file
          File.write(cache_file, JSON.pretty_generate(data))

          results[name] = {
            success: true,
            data: data,
            cached_at: Time.current,
            file_path: cache_file.to_s
          }

          Rails.logger.info "Successfully cached #{name} to #{cache_file}"
        else
          Rails.logger.error "Failed to fetch #{name}: HTTP #{response.code}"
          results[name] = {
            success: false,
            error: "HTTP #{response.code}",
            cached_at: Time.current
          }
        end
      rescue => e
        Rails.logger.error "Error fetching #{name}: #{e.message}"
        results[name] = {
          success: false,
          error: e.message,
          cached_at: Time.current
        }
      end
    end

    # Cache individual team data for all teams we might need
    cache_team_data

    results
  end

  def self.cache_team_data
    # List of team IDs we commonly need
    team_ids = [
      "130", # Michigan
      "167", # New Mexico
      "333", # Texas
      "158", # Ohio State
      "356", # Penn State
      "275", # Michigan State
      "239", # Wisconsin
      "275", # Iowa
      "275", # Nebraska
      "275", # Minnesota
      "275", # Northwestern
      "275", # Illinois
      "275", # Purdue
      "275", # Indiana
      "275", # Maryland
      "275" # Rutgers
    ]

    team_ids.each do |team_id|
      cache_individual_team(team_id)
    end
  end

  def self.cache_individual_team(team_id)
    url = "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/#{team_id}"

    begin
      response = HTTParty.get(url, timeout: 5)

      if response.success?
        data = JSON.parse(response.body)
        cache_file = cache_file_path("team_#{team_id}")

        File.write(cache_file, JSON.pretty_generate(data))
        Rails.logger.info "Cached team #{team_id} data"
      else
        Rails.logger.warn "Failed to fetch team #{team_id}: HTTP #{response.code}"
      end
    rescue => e
      Rails.logger.error "Error fetching team #{team_id}: #{e.message}"
    end
  end

  def self.get_cached_data(endpoint_name)
    cache_file = cache_file_path(endpoint_name)

    if File.exist?(cache_file)
      begin
        data = JSON.parse(File.read(cache_file))
        Rails.logger.info "Loaded cached data for #{endpoint_name}"
        data
      rescue => e
        Rails.logger.error "Error reading cached data for #{endpoint_name}: #{e.message}"
        nil
      end
    else
      Rails.logger.warn "No cached data found for #{endpoint_name}"
      nil
    end
  end

  def self.get_cached_team_data(team_id)
    get_cached_data("team_#{team_id}")
  end

  def self.cache_exists?(endpoint_name)
    File.exist?(cache_file_path(endpoint_name))
  end

  def self.cache_age(endpoint_name)
    cache_file = cache_file_path(endpoint_name)
    return nil unless File.exist?(cache_file)

    File.mtime(cache_file)
  end

  def self.clear_cache
    if Dir.exist?(CACHE_DIR)
      FileUtils.rm_rf(CACHE_DIR)
      Rails.logger.info "Cleared all cached API data"
    end
  end

  def self.cache_status
    status = {}

    ENDPOINTS.keys.each do |endpoint|
      status[endpoint] = {
        exists: cache_exists?(endpoint),
        age: cache_age(endpoint),
        file_path: cache_file_path(endpoint).to_s
      }
    end

    status
  end

  # Method to fetch game-specific data (odds, weather) and cache it
  def self.cache_game_data(game_id, away_team_id, home_team_id)
    initialize_cache_directory

    # Cache odds data
    odds_data = fetch_game_odds(away_team_id, home_team_id)
    if odds_data
      cache_file = cache_file_path("odds_#{away_team_id}_#{home_team_id}")
      File.write(cache_file, JSON.pretty_generate(odds_data))
    end

    # Cache weather data (even if it's null/empty to avoid repeated API calls)
    weather_data = fetch_game_weather(away_team_id, home_team_id)
    cache_file = cache_file_path("weather_#{away_team_id}_#{home_team_id}")
    File.write(cache_file, JSON.pretty_generate(weather_data || {}))
  end

  def self.get_cached_game_odds(away_team_id, home_team_id)
    get_cached_data("odds_#{away_team_id}_#{home_team_id}")
  end

  def self.get_cached_game_weather(away_team_id, home_team_id)
    get_cached_data("weather_#{away_team_id}_#{home_team_id}")
  end

  private

  def self.fetch_game_odds(away_team_id, home_team_id)
    # Try to find game ID first
    game_id = find_game_id(away_team_id, home_team_id)

    if game_id
      begin
        response = HTTParty.get(
          "https://site.api.espn.com/apis/site/v2/sports/football/college-football/summary?event=#{game_id}",
          timeout: 5
        )

        if response.success?
          data = JSON.parse(response.body)
          return data["pickcenter"] if data["pickcenter"]
        end
      rescue => e
        Rails.logger.error "Error fetching odds for game #{game_id}: #{e.message}"
      end
    end

    # Fallback to scoreboard method
    begin
      response = HTTParty.get(
        "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard",
        timeout: 5
      )

      if response.success?
        data = JSON.parse(response.body)
        events = data["events"] || []

        game_event = events.find do |event|
          if event["competitions"]&.first&.dig("competitors")
            competitors = event["competitions"].first["competitors"]
            away_id = competitors.find { |c| c["homeAway"] == "away" }&.dig("team", "id")
            home_id = competitors.find { |c| c["homeAway"] == "home" }&.dig("team", "id")
            away_id == away_team_id.to_s && home_id == home_team_id.to_s
          else
            false
          end
        end

        return game_event["competitions"].first["odds"] if game_event && game_event["competitions"]&.first&.dig("odds")
      end
    rescue => e
      Rails.logger.error "Error fetching odds from scoreboard: #{e.message}"
    end

    nil
  end

  def self.fetch_game_weather(away_team_id, home_team_id)
    game_id = find_game_id(away_team_id, home_team_id)

    if game_id
      begin
        response = HTTParty.get(
          "https://site.api.espn.com/apis/site/v2/sports/football/college-football/summary?event=#{game_id}",
          timeout: 5
        )

        if response.success?
          data = JSON.parse(response.body)
          return data["weather"] if data["weather"]
        end
      rescue => e
        Rails.logger.error "Error fetching weather for game #{game_id}: #{e.message}"
      end
    end

    # Fallback to scoreboard method
    begin
      response = HTTParty.get(
        "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard",
        timeout: 5
      )

      if response.success?
        data = JSON.parse(response.body)
        events = data["events"] || []

        game_event = events.find do |event|
          if event["competitions"]&.first&.dig("competitors")
            competitors = event["competitions"].first["competitors"]
            away_id = competitors.find { |c| c["homeAway"] == "away" }&.dig("team", "id")
            home_id = competitors.find { |c| c["homeAway"] == "home" }&.dig("team", "id")
            away_id == away_team_id.to_s && home_id == home_team_id.to_s
          else
            false
          end
        end

        return game_event["weather"] if game_event && game_event["weather"]
      end
    rescue => e
      Rails.logger.error "Error fetching weather from scoreboard: #{e.message}"
    end

    nil
  end

  def self.find_game_id(away_team_id, home_team_id)
    begin
      response = HTTParty.get(
        "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/Michigan/schedule?season=2025&seasontype=2",
        timeout: 5
      )

      if response.success?
        data = JSON.parse(response.body)
        events = data["events"] || []

        matching_event = events.find do |event|
          if event["competitions"]&.first&.dig("competitors")
            competitors = event["competitions"].first["competitors"]
            away_id = competitors.find { |c| c["homeAway"] == "away" }&.dig("team", "id")
            home_id = competitors.find { |c| c["homeAway"] == "home" }&.dig("team", "id")
            away_id == away_team_id.to_s && home_id == home_team_id.to_s
          else
            false
          end
        end

        return matching_event["id"] if matching_event
      end
    rescue => e
      Rails.logger.error "Failed to find game ID: #{e.message}"
    end

    nil
  end
end
