import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "gameRow"]
  static values = { 
    michiganTeamId: { type: Number, default: 130 }
  }

  connect() {
    console.log("Game filter controller connected")
    console.log("Found", this.gameRowTargets.length, "game rows")
    console.log("Found button target:", this.hasButtonTarget)
    console.log("Michigan team ID set to:", this.michiganTeamIdValue)
    
    // Log all team IDs to see what we're working with
    this.gameRowTargets.forEach((row, index) => {
      const homeTeamId = this.getHomeTeamId(row)
      console.log(`Row ${index}: homeTeamId = ${homeTeamId}`)
    })
    
    this.isHomeGamesOnly = false
    this.updateButtonText()
  }

  toggle() {
    console.log("Toggle clicked, current state:", this.isHomeGamesOnly)
    this.isHomeGamesOnly = !this.isHomeGamesOnly
    this.updateButtonText()
    this.filterGames()
  }

  updateButtonText() {
    if (this.isHomeGamesOnly) {
      this.buttonTarget.textContent = "Show All Games"
      this.buttonTarget.classList.remove("bg-blue-500", "hover:bg-blue-600")
      this.buttonTarget.classList.add("bg-green-500", "hover:bg-green-600")
    } else {
      this.buttonTarget.textContent = "Home Games Only"
      this.buttonTarget.classList.remove("bg-green-500", "hover:bg-green-600")
      this.buttonTarget.classList.add("bg-blue-500", "hover:bg-blue-600")
    }
  }

  filterGames() {
    console.log("Filtering games, home games only:", this.isHomeGamesOnly)
    console.log("Looking for Michigan team ID:", this.michiganTeamIdValue)
    
    let visibleCount = 0;
    let hiddenCount = 0;
    
    this.gameRowTargets.forEach((row, index) => {
      const homeTeamId = this.getHomeTeamId(row)
      const shouldShow = !this.isHomeGamesOnly || homeTeamId === this.michiganTeamIdValue
      console.log(`Row ${index}: homeTeamId = ${homeTeamId}, should show: ${shouldShow}`)
      
      if (this.isHomeGamesOnly) {
        // Show only if Michigan is home team
        if (homeTeamId === this.michiganTeamIdValue) {
          row.style.display = ""
          row.classList.remove("hidden")
          visibleCount++;
          console.log(`Row ${index}: SHOWING (Michigan home game)`)
        } else {
          row.style.display = "none"
          row.classList.add("hidden")
          hiddenCount++;
          console.log(`Row ${index}: HIDING (Michigan away game)`)
        }
      } else {
        // Show all games
        row.style.display = ""
        row.classList.remove("hidden")
        visibleCount++;
        console.log(`Row ${index}: SHOWING (all games mode)`)
      }
    })
    
    console.log(`Filter complete: ${visibleCount} visible, ${hiddenCount} hidden`)
  }

  getHomeTeamId(row) {
    // Extract home team ID from the row data
    const homeTeamId = row.dataset.homeTeamId
    console.log("Raw homeTeamId from dataset:", homeTeamId)
    return parseInt(homeTeamId) || 0
  }
} 