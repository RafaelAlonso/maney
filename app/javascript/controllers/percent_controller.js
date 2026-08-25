import { Controller } from "@hotwired/stimulus"

// The percentage switch above the Início category list. Each card renders BOTH
// readings (share of income, share of the month's spending); this shows one and
// hides the other, with no server round-trip, and remembers the choice in a
// cookie the server reads on the next load to paint the right one from the first
// byte — the same cookie-first pattern as the theme toggle, so neither flashes.
export default class extends Controller {
  static targets = ["earnings", "expenses", "option"]
  static values = { mode: String }

  connect() {
    this.apply(this.modeValue || "expenses")
  }

  // Each button carries the mode it selects, so clicking the active one is a
  // no-op rather than flipping away from it.
  select(event) {
    this.apply(event.currentTarget.dataset.mode)
    document.cookie = `home_percent=${this.modeValue}; path=/; max-age=31536000; samesite=lax`
  }

  apply(mode) {
    this.modeValue = mode
    this.earningsTargets.forEach((el) => el.classList.toggle("hidden", mode !== "earnings"))
    this.expensesTargets.forEach((el) => el.classList.toggle("hidden", mode !== "expenses"))
    this.optionTargets.forEach((el) => {
      const active = el.dataset.mode === mode
      el.classList.toggle("bg-surface", active)
      el.classList.toggle("text-text", active)
      el.classList.toggle("shadow-sm", active)
      el.classList.toggle("text-muted", !active)
      el.setAttribute("aria-pressed", active ? "true" : "false")
    })
  }
}
