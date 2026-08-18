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

// A bar dataset names itself (`dataset.label`) and parses to `{x, y}`; a pie
// slice names itself per point (`item.label`) and parses to a bare number.
// Reading both here keeps the tooltip generic, so the presenters stay the only
// place that knows what kind of chart is being drawn.
//
// `seriesLabel` is deliberately `dataset.label` alone, with no fallback to
// `item.label`: Chart.js's default *title* callback already prints `item.label`
// for a pie or doughnut, so falling back would name the slice twice: title
// "padaria" over body "padaria: R$ 220,00". A pie tooltip reads title + amount.
const seriesLabel = (item) => item.dataset.label ?? null
const seriesValue = (item) => (typeof item.parsed === "number" ? item.parsed : item.parsed?.y)

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
    this.canvas = this.element.tagName === "CANVAS" ? this.element : this.element.querySelector("canvas")
    this.rawDatasets = this.configValue.data.datasets
    this.recolor = this.recolor.bind(this)
    document.addEventListener("theme:change", this.recolor)
    this.chart = new Chart(this.canvas, this.resolvedConfig(this.rawDatasets))
  }

  disconnect() {
    document.removeEventListener("theme:change", this.recolor)
    this.chart?.destroy()
    this.chart = null
  }

  // Rebuild a render-ready config from raw (token-carrying) datasets: resolve
  // every `var(--x)` against the current theme, then layer the currency
  // callbacks on top. Canvas cannot read CSS variables itself, so the color
  // must be a concrete string by the time it reaches Chart.js.
  resolvedConfig(rawDatasets) {
    const raw = { ...this.configValue, data: { ...this.configValue.data, datasets: rawDatasets } }
    return this.withCurrencyFormatting(this.resolveVars(raw))
  }

  // On a manual theme flip the page recolors via CSS with no reload; the canvas
  // holds colors resolved at render time, so re-resolve from the raw datasets
  // currently displayed (the profit chart keeps `rawDatasets` pointed at its
  // active mode) and repaint. Reassigning `options` too keeps grid/axis/legend
  // ink in step with the theme.
  recolor() {
    if (!this.chart) return
    const config = this.resolvedConfig(this.rawDatasets)
    this.chart.data.datasets = config.data.datasets
    this.chart.options = config.options
    this.chart.update()
  }

  // Deep-copy `value`, replacing any string of the exact form `var(--name)`
  // with its computed value on <html>. Non-var strings (hex, "transparent"),
  // numbers and null pass through untouched — so a config carrying only hex
  // behaves exactly as before this method existed.
  resolveVars(value) {
    if (Array.isArray(value)) return value.map((item) => this.resolveVars(item))
    if (value && typeof value === "object") {
      return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, this.resolveVars(item)]))
    }
    if (typeof value === "string") {
      const match = value.match(/^var\((--[\w-]+)\)$/)
      if (match) return getComputedStyle(document.documentElement).getPropertyValue(match[1]).trim()
    }
    return value
  }

  withCurrencyFormatting(config) {
    const options = config.options || {}

    const nextOptions = {
      ...options,
      plugins: {
        ...(options.plugins || {}),
        tooltip: {
          ...this.tooltipOptions(options),
          // `Intl.NumberFormat` coerces `null` to `0` without throwing, so an
          // unguarded call would print "R$ 0,00" for a month with no data —
          // exactly the fabricated zero this app forbids everywhere else. A
          // gap month shows the series name alone instead.
          callbacks: {
            label: (item) => {
              const value = seriesValue(item)
              const name = seriesLabel(item)
              if (value == null) return name ?? ""
              return name == null ? BRL.format(value) : `${name}: ${BRL.format(value)}`
            }
          }
        }
      }
    }

    // Only a chart that declares a value axis gets one. Adding `scales.y`
    // unconditionally would hand a pie an axis it has no use for and would draw
    // one on it.
    if (options.scales) {
      const y = options.scales.y || {}
      nextOptions.scales = {
        ...options.scales,
        y: { ...y, ticks: { ...(y.ticks || {}), callback: axisTick } }
      }
    }

    return { ...config, options: nextOptions }
  }

  // `itemSort: "desc"` is a sentinel from the Ruby presenter: Chart.js wants a
  // comparator here, and a function cannot survive JSON.
  tooltipOptions(options) {
    const tooltip = { ...((options.plugins || {}).tooltip || {}) }
    if (tooltip.itemSort === "desc") {
      // Through `seriesValue`, not `parsed.y`, for the same reason the label
      // callback is: a pie parses to a bare number, and `undefined - undefined`
      // is NaN — a comparator returning NaN leaves the order arbitrary rather
      // than descending. A gap (null) sorts last.
      tooltip.itemSort = (a, b) => {
        const [ first, second ] = [ seriesValue(b) ?? -Infinity, seriesValue(a) ?? -Infinity ]
        return first === second ? 0 : first - second
      }
    }
    return tooltip
  }
}
