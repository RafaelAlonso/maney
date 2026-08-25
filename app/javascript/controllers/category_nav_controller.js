import { Controller } from "@hotwired/stimulus"

// The jump-to-category select on a category dashboard: navigate to the chosen
// category's dashboard on change. Each option's value is the full path (month
// included), so there is nothing to build here — just visit it. Turbo drives the
// visit when present so it stays a same-page swap; a plain assign is the fallback.
export default class extends Controller {
  navigate(event) {
    const path = event.target.value
    if (!path) return
    if (window.Turbo) window.Turbo.visit(path)
    else window.location.assign(path)
  }
}
