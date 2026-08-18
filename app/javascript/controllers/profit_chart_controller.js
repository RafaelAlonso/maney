import ChartController from "controllers/chart_controller"

// The profit chart carries all three modes' datasets and swaps them on the live
// Chart.js instance, so switching never round-trips to the server.
export default class extends ChartController {
  static values = { config: Object, modes: Object }
  static targets = ["mode"]

  select(event) {
    const datasets = this.modesValue[event.params.mode]
    if (!datasets) return

    this.rawDatasets = datasets
    this.chart.data.datasets = this.resolvedConfig(datasets).data.datasets
    this.chart.update()
    this.modeTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.profitChartModeParam === event.params.mode))
    })
  }
}
