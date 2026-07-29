import { Controller } from "@hotwired/stimulus"

// Imported for its side effect, and read off the global — not a named import.
// Chart.js 4.5.1 ships no single-file ESM build (`dist/chart.js` imports a
// sibling chunk that cannot be pinned or served through Propshaft), so
// config/importmap.rb pins the self-contained UMD bundle instead. Loaded as a
// module it takes its global branch and defines `window.Chart`, which is its
// only surface here. It also registers every component on load, so there is no
// `Chart.register(...registerables)` call to make. Do not "fix" this back into
// `import { Chart } from "chart.js"` — that import cannot resolve.
import "chart.js"

const BRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" })
const BRL_ROUND = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 })

// Axis ticks land on round numbers, so ",00" on every one of them is noise that
// also costs the plot ~25px of width on a phone — enough to force the month
// labels to tilt. A tick that is not whole still shows its cents rather than
// rounding to a value the reader cannot find in the data.
const axisTick = (value) => (Number.isInteger(value) ? BRL_ROUND : BRL).format(value)

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
        scales: { ...scales, y: { ...y, ticks: { ...(y.ticks || {}), callback: axisTick } } },
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
