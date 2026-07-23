import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cardSection", "installmentSection", "installmentFields", "amountLabel", "categoryOption"]

  connect() { this.refresh() }

  refresh() {
    const credit = this.method === "credit"
    this.cardSectionTarget.hidden = !credit
    this.installmentSectionTarget.hidden = !credit
    // Leaving credit must clear both the installment box and the card choice
    // right here — not just hide their sections. `hidden` does not disable an
    // input, so a checked installment box and a chosen card would still submit
    // even though they're no longer visible: pick credit, choose a card, check
    // installment, then switch to debit/cash and Save was reachable with no
    // devtools (Fix 1). The server rejects that combination now too, but the
    // invalid state shouldn't be reachable from the UI in the first place.
    if (!credit) {
      if (this.installmentCheckbox) this.installmentCheckbox.checked = false
      const cardSelect = this.element.querySelector('select[name="expense_entry[card_id]"]')
      if (cardSelect) cardSelect.value = ""
    }
    this.categoryOptionTargets.forEach(option => {
      const blocked = credit && option.dataset.role === "credit_card"
      option.disabled = blocked
      option.hidden = blocked
      // This <select> has no `multiple`: if the blocked option is the only one
      // selected, simply unselecting it (`selected = false`) leaves the <select>
      // with no option selected, and the browser silently falls back to the
      // first enabled option in DOM order — an arbitrary category as soon as the
      // user has more than two options, not their intent. This is reachable with
      // no click at all: when the server rejects a credit expense in the reserved
      // card category, Rails re-renders the form with that option still `selected`
      // and the credit radio still `checked`; `connect()` calls `refresh()` and
      // the swap would happen on the re-render, not on a user action. So we
      // explicitly select "outros" instead — the same category the server already
      // uses when `category_id` comes in blank (see `ExpenseEntry#category`), so
      // the fallback stays deterministic and semantically correct, not a browser decision.
      if (blocked && option.selected) {
        option.selected = false
        const fallback = this.categoryOptionTargets.find(o => o.dataset.role === "others")
        if (fallback) fallback.selected = true
      }
    })
    const parcelado = credit && this.installmentCheckbox?.checked
    this.installmentFieldsTarget.hidden = !parcelado
    this.amountLabelTarget.textContent = parcelado ? "Valor total (R$)" : "Valor (R$)"
  }

  get method() {
    return this.element.querySelector('input[name="expense_entry[payment_method]"]:checked')?.value
  }

  get installmentCheckbox() {
    return this.element.querySelector('input[name="expense_entry[installment]"][type="checkbox"]')
  }
}
