class ProwlersController < ApplicationController
  require 'nokogiri'
  require 'open-uri'

  def index
    browser = Watir::Browser.new
    browser.goto 'https://www.phprowlers.com/stats#/team-schedule'
    doc = Nokogiri::HTML.parse(browser.html).css('.schedule > .game')
    games = []

    doc.each do |game|
        teams = game.css('.team')
        team1_city = teams[0].css('.city').text
        team1_name = teams[0].css('.name').text
        team1_score = teams[0].css('.score').text

        team2_city = teams[1].css('.city').text
        team2_name = teams[1].css('.name').text
        team2_score = teams[1].css('.score').text

        at_vs = game.css('.at-vs').text
        status = game.css('.status').text
        result = game.css('.result').text
        
        games.push({
            datetime: game.css('.datetime').text,
            team1: {
                city: team1_city,
                name: team1_name,
                score: team1_score
            },
            team2: {
                city: team2_city,
                name: team2_name,
                score: team2_score
            },
            at_vs: at_vs,
            status: status,
            result: result
        })
    end

    render json: games
  end
end