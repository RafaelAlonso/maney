import { Controller } from "@hotwired/stimulus"

// Turns the month label in the nav into a jump-to-month control. A native
// <input type="month"> sits invisibly over the label; clicking the label opens
// its picker, and choosing a month navigates straight there — no stepping through
// the ‹ › arrows a month at a time. The input's value is already "YYYY-MM", which
// is exactly the `?month=` the app uses, so the target URL is the caller's path
// template with the chosen month dropped in.
export default class extends Controller {
  static targets = ["input"]
  static values = { template: String }

  open() {
    if (this.inputTarget.showPicker) this.inputTarget.showPicker()
    else this.inputTarget.focus()
  }

  navigate() {
    const month = this.inputTarget.value
    if (!month) return
    const url = this.templateValue.replace("__MONTH__", month)
    if (window.Turbo) window.Turbo.visit(url)
    else window.location.assign(url)
  }
}
