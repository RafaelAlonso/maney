import { Controller } from "@hotwired/stimulus"

// Both Análise filters submit on change: a "Ver" button would be one tap too
// many on the controls that govern the whole page. The button stays in the DOM,
// hidden, as a fallback submit affordance.
export default class extends Controller {
  submit() {
    this.element.form.requestSubmit()
  }
}
