import { Controller } from "@hotwired/stimulus"

// A folded section opened by a button: toggles the panel's `hidden` and the
// button's aria-expanded together, so assistive tech hears the same state the
// screen shows. Starts folded in the markup — nothing moves on connect.
export default class extends Controller {
  static targets = ["button", "panel"]

  toggle() {
    const open = this.panelTarget.hidden
    this.panelTarget.hidden = !open
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
