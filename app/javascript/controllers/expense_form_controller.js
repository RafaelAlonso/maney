import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cardSection", "installmentSection", "installmentFields", "amountLabel", "categoryOption"]

  connect() { this.refresh() }

  refresh() {
    const credit = this.method === "credit"
    this.cardSectionTarget.hidden = !credit
    this.installmentSectionTarget.hidden = !credit
    // Leaving crédito must clear both parcelado and the card choice right
    // here — not just hide their sections. `hidden` does not disable an
    // input, so a checked "parcelado" box and a chosen card would still
    // submit even though they're no longer visible: pick crédito, choose a
    // card, check parcelado, then switch to débito/dinheiro and Salvar was
    // reachable with no devtools (Fix 1). The server rejects that
    // combination now too, but the invalid state shouldn't be reachable
    // from the UI in the first place.
    if (!credit) {
      if (this.installmentCheckbox) this.installmentCheckbox.checked = false
      const cardSelect = this.element.querySelector('select[name="expense_entry[card_id]"]')
      if (cardSelect) cardSelect.value = ""
    }
    this.categoryOptionTargets.forEach(option => {
      const blocked = credit && option.dataset.role === "credit_card"
      option.disabled = blocked
      option.hidden = blocked
      // Este <select> não tem `multiple`: se a option bloqueada for a única
      // selecionada, simplesmente desmarcá-la (`selected = false`) deixa o
      // <select> sem nenhuma option selecionada, e o navegador cai
      // silenciosamente na primeira option habilitada em ordem de DOM — uma
      // categoria arbitrária assim que o usuário tiver mais de duas opções,
      // não a intenção dele. Isso é alcançável sem clique nenhum: quando o
      // servidor rejeita um gasto crédito na categoria reservada de cartão,
      // Rails re-renderiza o form com essa option ainda `selected` e o rádio
      // crédito ainda `checked`; `connect()` chama `refresh()` e a troca
      // aconteceria na re-renderização, não numa ação do usuário. Por isso
      // selecionamos explicitamente "outros" no lugar — mesma categoria que
      // o servidor já usa quando `category_id` vem em branco (ver
      // `ExpenseEntry#category`), então o fallback fica determinístico e
      // semanticamente certo, não uma decisão do navegador.
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
