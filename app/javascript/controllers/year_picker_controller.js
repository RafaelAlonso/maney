import { Controller } from "@hotwired/stimulus"

// The year picker submits on change: a separate "Ver" button would be one tap
// too many on the only control that governs the whole page. The button stays in
// the DOM, hidden, so the form is still submittable without JavaScript.
export default class extends Controller {
  submit() {
    this.element.form.requestSubmit()
  }
}
