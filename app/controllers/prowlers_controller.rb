class ProwlersController < ApplicationController
  require 'nokogiri'
  require 'open-uri'
  require 'selenium-webdriver'
  
  def index
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument("--no-sandbox");
    options.add_argument("--disable-gpu");
    driver = Selenium::WebDriver.for(:chrome, options: options)
    
    url = 'https://www.phprowlers.com/stats#/team-schedule'
    driver.get(url)
    wait = Selenium::WebDriver::Wait.new(timeout: 2)
    wait.until { driver.find_element(class: 'team-schedule') }
    page_html = driver.page_source
    doc = Nokogiri::HTML(page_html).css('.schedule > .game')
    games = []

    doc.each do |game|
        teams = game.css('.team')
        team1_city = teams[0].css('.city').text
        team1_name = teams[0].css('.name').text
        team1_score = teams[0].css('.score').text

        at_vs = game.css('.at-vs').text

        team2_city = teams[1].css('.city').text
        team2_name = teams[1].css('.name').text
        team2_score = teams[1].css('.score').text

        status = game.css('.status').text
        result = game.css('.result').text
        
        date = DateTime.parse(game.css('.datetime').text)
        
        if at_vs == 'vs'
          location = team1_city
        elsif at_vs == 'at'
          location = team2_city 
        end

        games.push({
            datetime: date,
            team1: {
                city: team1_city,
                name: team1_name,
                score: team1_score
            },
            at_vs: at_vs,
            team2: {
                city: team2_city,
                name: team2_name,
                score: team2_score
            },
            location: location,
            status: status,
            result: result
        })
    end

    render json: games
  end

  def calendar
    require 'net/http'
    require 'json'
    require 'icalendar'
    cal = Icalendar::Calendar.new

    url = URI.parse('http://localhost:3000/prowlers.json')
    response = Net::HTTP.get_response(url)
    games = JSON.parse(response.body)

    games.each do |game|
      event = Icalendar::Event.new
      event.dtstart = DateTime.parse(game['datetime'])
      event.dtend = DateTime.parse(game['datetime']) + 3.hours
      event.summary = "#{game['team1']['name']} #{game['at_vs']} #{game['team2']['name']}"
      event.location =  "#{game['location']}"
      cal.add_event(event)
    end

    cal.publish
    respond_to do |format|
      format.html
      format.ics { render plain: cal.to_ical }
    end
  end
end