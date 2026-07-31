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

// Bound explicitly so a pin regression (the global not being defined) throws
// a clear ReferenceError right here, next to the comment explaining the
// vendoring, instead of failing deep inside `connect()`.
const { Chart } = window

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
// The tooltip label reads "series: value". Today Chart.js's own
// `interaction: { mode: "index" }` skips a dataset at a hovered index when
// its parsed value is null, so the label callback rarely sees one in
// practice — but that is Chart.js internals, not a contract this file can
// lean on (a future chart may switch interaction modes), so the callback
// still guards for it explicitly.
//
// `itemSort` is a second case of the same JSON boundary: the Ruby presenter
// can only emit the sentinel string "desc", not the comparator function
// Chart.js actually wants, so `tooltipOptions` translates it here.
export default class extends Controller {
  static values = { config: Object }

  connect() {
    const canvas = this.element.tagName === "CANVAS" ? this.element : this.element.querySelector("canvas")
    this.chart = new Chart(canvas, this.withCurrencyFormatting(this.configValue))
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
            ...this.tooltipOptions(options),
            // `Intl.NumberFormat` coerces `null` to `0` without throwing, so an
            // unguarded call would print "R$ 0,00" for a month with no data —
            // exactly the fabricated zero this app forbids everywhere else. A
            // gap month shows the series name alone instead.
            callbacks: {
              label: (item) =>
                item.parsed.y == null
                  ? item.dataset.label
                  : `${item.dataset.label}: ${BRL.format(item.parsed.y)}`
            }
          }
        }
      }
    }
  }

  // `itemSort: "desc"` is a sentinel from the Ruby presenter: Chart.js wants a
  // comparator here, and a function cannot survive JSON.
  tooltipOptions(options) {
    const tooltip = { ...((options.plugins || {}).tooltip || {}) }
    if (tooltip.itemSort === "desc") {
      tooltip.itemSort = (a, b) => b.parsed.y - a.parsed.y
    }
    return tooltip
  }
}
