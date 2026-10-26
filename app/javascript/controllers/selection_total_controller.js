import { Controller } from "@hotwired/stimulus"

// Tick rows to see what they add up to. Purely client-side: each checkbox
// carries the cents of its row in `data-cents`, and nothing is saved — a reload
// or a month change starts with nothing selected.
export default class extends Controller {
  static targets = ["item", "bar", "count", "total"]

  // Recomputed on connect too: a back-navigation can restore checked boxes
  // from the snapshot, and the bar must agree with them.
  connect() { this.refresh() }

  refresh() {
    const checked = this.itemTargets.filter((item) => item.checked)
    const cents = checked.reduce((sum, item) => sum + Number(item.dataset.cents), 0)
    this.barTarget.hidden = checked.length === 0
    this.countTarget.textContent = checked.length === 1 ? "1 selecionado" : `${checked.length} selecionados`
    this.totalTarget.textContent = this.brl(cents)
  }

  clear() {
    this.itemTargets.forEach((item) => { item.checked = false })
    this.refresh()
  }

  // Same shape as ApplicationHelper#brl ("R$ 1.234,56", "-R$ 5,00"). Intl puts
  // a non-breaking space after "R$"; the server's helper uses a plain one.
  brl(cents) {
    const formatted = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      .format(Math.abs(cents) / 100)
    return `${cents < 0 ? "-" : ""}R$ ${formatted}`
  }
}
