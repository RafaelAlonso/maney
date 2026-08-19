import { Controller } from "@hotwired/stimulus"

// The mobile "Mais" slide-in. Opens over a scrim; closes on scrim click, Escape,
// selecting a destination, or a theme flip — sliding back out to the (updated)
// underlying view. Closing on theme:change is what makes toggling the theme
// return the user to the recolored screen (the toggle itself lives in here).
export default class extends Controller {
  static targets = ["panel", "scrim"]

  connect() {
    this.close = this.close.bind(this)
    this.onKey = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("theme:change", this.close)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("theme:change", this.close)
  }

  open() {
    this.scrimTarget.hidden = false
    this.panelTarget.classList.remove("translate-x-full")
  }

  close() {
    this.panelTarget.classList.add("translate-x-full")
    this.scrimTarget.hidden = true
  }
}
