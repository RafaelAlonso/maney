import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const BRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" })

// Renders a Chart.js config built server-side (app/presenters/analysis). The
// only thing added here is money formatting, because a Chart.js callback is a
// function and cannot survive the trip through JSON.
//
// In the tooltip the value leads and the series name follows: the reader
// already knows which month and which series they are pointing at, and what
// they came for is the number. A month outside the timeline has no value at
// all, so it shows the series name alone rather than a fabricated R$ 0,00.
export default class extends Controller {
  static values = { config: Object }

  connect() {
    this.chart = new Chart(this.element, this.withCurrencyFormatting(this.configValue))
  }

  disconnect() {
    this.chart?.destroy()
    this.chart = null
  }

  withCurrencyFormatting(config) {
    const options = config.options || {}
    const scales = options.scales || {}
    const y = scales.y || {}

    return {
      ...config,
      options: {
        ...options,
        scales: { ...scales, y: { ...y, ticks: { ...(y.ticks || {}), callback: (value) => BRL.format(value) } } },
        plugins: {
          ...(options.plugins || {}),
          tooltip: {
            ...((options.plugins || {}).tooltip || {}),
            usePointStyle: true,
            callbacks: {
              label: (item) => {
                const value = item.parsed.y
                return value == null ? item.dataset.label : `${BRL.format(value)} · ${item.dataset.label}`
              }
            }
          }
        }
      }
    }
  }
}
