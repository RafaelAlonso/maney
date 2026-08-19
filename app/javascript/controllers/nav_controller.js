import { Controller } from "@hotwired/stimulus"

// Desktop top-nav overflow: show as many destinations inline as fit, fold the
// rest into the "Mais" dropdown, and re-run on resize. If the active destination
// is folded, tint the "Mais" button so the current section still reads.
export default class extends Controller {
  static targets = ["list", "item", "more", "menu"]

  connect() {
    this.ordered = [...this.itemTargets]
    this.reflow = this.reflow.bind(this)
    this.observer = new ResizeObserver(this.reflow)
    this.observer.observe(this.element)
    this.reflow()
    this.closeOnOutside = (event) => { if (!this.moreTarget.contains(event.target)) this.closeMore() }
    document.addEventListener("click", this.closeOnOutside)
  }

  disconnect() {
    this.observer.disconnect()
    document.removeEventListener("click", this.closeOnOutside)
  }

  toggleMore(event) {
    event.stopPropagation()
    this.menuTarget.hidden ? this.openMore() : this.closeMore()
  }

  openMore() {
    this.menuTarget.hidden = false
    this.moreButton.setAttribute("aria-expanded", "true")
  }

  closeMore() {
    this.menuTarget.hidden = true
    this.moreButton.setAttribute("aria-expanded", "false")
  }

  get moreButton() { return this.moreTarget.querySelector("button") }

  get inlineItems() { return this.ordered.filter((item) => item.parentElement === this.listTarget) }

  // Reset every item inline (row styling), then move the last inline item into
  // the dropdown until the row fits. The "Mais" control is visible while we
  // measure, so its width is reserved and the fit we compute is the one seen.
  reflow() {
    this.ordered.forEach((item) => {
      item.classList.add("shrink-0")
      item.classList.remove("block", "px-2", "py-1")
      this.listTarget.insertBefore(item, this.moreTarget)
    })
    this.moreTarget.hidden = false

    while (this.listTarget.scrollWidth > this.listTarget.clientWidth && this.inlineItems.length) {
      const last = this.inlineItems[this.inlineItems.length - 1]
      last.classList.remove("shrink-0")
      last.classList.add("block", "px-2", "py-1")
      this.menuTarget.insertBefore(last, this.menuTarget.firstChild)
    }

    const folded = this.menuTarget.children.length > 0
    this.moreTarget.hidden = !folded
    const activeFolded = folded && this.menuTarget.querySelector('[aria-current="page"]') !== null
    this.moreButton.classList.toggle("text-accent", activeFolded)
  }
}
