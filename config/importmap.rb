# Pin npm packages by running ./bin/importmap

pin "application"
pin "pwa"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# The UMD build, not the ESM one: Chart.js 4.5.1 publishes no single-file ESM —
# `dist/chart.js` imports a sibling chunk that `bin/importmap pin` does not
# download and that Propshaft cannot serve at the undigested relative path the
# import resolves to. The UMD bundle is self-contained (@kurkle/color included,
# which is why there is no pin for it) and registers every Chart.js component on
# load. Keep the version comment — `bin/importmap audit` parses it.
pin "chart.js", to: "chart.umd.js" # @4.5.1
