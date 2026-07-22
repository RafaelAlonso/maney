import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cardSection", "installmentSection", "installmentFields", "amountLabel", "categoryOption"]

  connect() { this.refresh() }

  refresh() {
    const credit = this.method === "credit"
    this.cardSectionTarget.hidden = !credit
    this.installmentSectionTarget.hidden = !credit
    this.categoryOptionTargets.forEach(option => {
      const blocked = credit && option.dataset.role === "credit_card"
      option.disabled = blocked
      option.hidden = blocked
      if (blocked && option.selected) option.selected = false
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
