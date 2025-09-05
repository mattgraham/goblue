# API Caching for Development

This application now uses cached API data for development to avoid hitting the ESPN API repeatedly.

## How it works

- All ESPN API responses are cached locally in `tmp/api_cache/` as JSON files
- The dashboard controller checks for cached data first before making API calls
- If cached data exists, it uses that; otherwise it falls back to live API calls

## Cache Management

### Fetch all API data
```bash
rails api_cache:fetch_all
```

### Check cache status
```bash
rails api_cache:status
```

### Clear all cached data
```bash
rails api_cache:clear
```

### Cache individual team data
```bash
rails api_cache:cache_team[TEAM_ID]
# Example: rails api_cache:cache_team[130]
```

### Cache game-specific data (odds and weather)
```bash
rails api_cache:cache_game[AWAY_TEAM_ID,HOME_TEAM_ID]
# Example: rails api_cache:cache_game[167,130]
```

## Cached Endpoints

The following API endpoints are cached:

- **michigan_schedule**: Michigan's 2025 schedule
- **current_week**: Current week information from scoreboard
- **ap_rankings**: AP Top 25 rankings
- **michigan_team**: Michigan team data and records
- **scoreboard**: Current week's scoreboard
- **team_XXX**: Individual team data for common teams
- **odds_XXX_XXX**: Game-specific odds data
- **weather_XXX_XXX**: Game-specific weather data

## Cache Files Location

All cache files are stored in: `tmp/api_cache/`

## Benefits

- **Faster development**: No waiting for API responses
- **Offline development**: Works without internet connection
- **Consistent data**: Same data across development sessions
- **Reduced API usage**: Avoids hitting ESPN API limits

## Notes

- Cache files are automatically created when you run `rails api_cache:fetch_all`
- The application will fall back to live API calls if cached data is not available
- Cache files are not committed to git (they're in `tmp/` directory)
- To refresh data, simply run the fetch command again
