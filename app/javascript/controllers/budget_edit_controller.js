import { Controller } from "@hotwired/stimulus"

// Click-to-edit for a category's budget on the month view.
//
// Visibility is toggled through Tailwind's `hidden` class rather than the
// `hidden` attribute: the form carries `display: inline` from a class, and a
// class selector beats the user agent's `[hidden] { display: none }` on
// specificity — setting `.hidden = true` would leave the input on screen.
export default class extends Controller {
  static targets = ["display", "form", "input"]

  edit() {
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.formTarget.classList.add("inline")
    this.inputTarget.focus()
    this.inputTarget.select()
  }
}
