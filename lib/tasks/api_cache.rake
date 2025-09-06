namespace :api_cache do
  desc "Fetch and cache all API data for development"
  task fetch_all: :environment do
    puts "Starting API data caching..."
    puts "This will fetch all ESPN API data and store it locally for development."

    results = ApiCacheService.fetch_and_cache_all_data

    puts "\n=== Caching Results ==="
    results.each do |endpoint, result|
      if result[:success]
        puts "✅ #{endpoint}: Successfully cached"
        puts "   File: #{result[:file_path]}"
        puts "   Cached at: #{result[:cached_at]}"
      else
        puts "❌ #{endpoint}: Failed - #{result[:error]}"
      end
      puts
    end

    puts "=== Cache Status ==="
    status = ApiCacheService.cache_status
    status.each do |endpoint, info|
      if info[:exists]
        age = info[:age]
        age_str = age ? "Age: #{((Time.current - age) / 1.hour).round(2)} hours" : "Unknown age"
        puts "📁 #{endpoint}: #{age_str}"
      else
        puts "❌ #{endpoint}: Not cached"
      end
    end

    puts "\n🎉 API caching complete! Your development environment will now use cached data."
    puts "To refresh the cache, run: rails api_cache:fetch_all"
    puts "To clear the cache, run: rails api_cache:clear"
  end

  desc "Clear all cached API data"
  task clear: :environment do
    puts "Clearing all cached API data..."
    ApiCacheService.clear_cache
    puts "✅ API cache cleared successfully!"
  end

  desc "Clear Rails cache"
  task clear_rails: :environment do
    puts "Clearing Rails cache..."
    Rails.cache.clear
    puts "✅ Rails cache cleared successfully!"
  end

  desc "Clear all caches (API + Rails)"
  task clear_all: :environment do
    puts "Clearing all caches..."
    ApiCacheService.clear_cache
    Rails.cache.clear
    puts "✅ All caches cleared successfully!"
  end

  desc "Show cache status"
  task status: :environment do
    puts "=== API Cache Status ==="
    status = ApiCacheService.cache_status

    status.each do |endpoint, info|
      if info[:exists]
        age = info[:age]
        if age
          age_hours = ((Time.current - age) / 1.hour).round(2)
          age_str = "#{age_hours} hours old"
        else
          age_str = "Unknown age"
        end
        puts "📁 #{endpoint}: #{age_str}"
        puts "   File: #{info[:file_path]}"
      else
        puts "❌ #{endpoint}: Not cached"
      end
      puts
    end
  end

  desc "Cache individual team data"
  task :cache_team, [ :team_id ] => :environment do |t, args|
    if args[:team_id]
      puts "Caching data for team #{args[:team_id]}..."
      ApiCacheService.cache_individual_team(args[:team_id])
      puts "✅ Team #{args[:team_id]} data cached successfully!"
    else
      puts "Usage: rails api_cache:cache_team[TEAM_ID]"
      puts "Example: rails api_cache:cache_team[130]"
    end
  end

  desc "Cache game-specific data (odds and weather)"
  task :cache_game, [ :away_team_id, :home_team_id ] => :environment do |t, args|
    if args[:away_team_id] && args[:home_team_id]
      puts "Caching game data for #{args[:away_team_id]} vs #{args[:home_team_id]}..."
      ApiCacheService.cache_game_data(nil, args[:away_team_id], args[:home_team_id])
      puts "✅ Game data cached successfully!"
    else
      puts "Usage: rails api_cache:cache_game[AWAY_TEAM_ID,HOME_TEAM_ID]"
      puts "Example: rails api_cache:cache_game[167,130]"
    end
  end
end
