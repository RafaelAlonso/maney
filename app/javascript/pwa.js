if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker")
}

// The browser's bfcache restores a live page without any network request, so
// neither Turbo nor the service worker sees it. Reloading sends it through the
// worker, which answers with the no-connection screen.
addEventListener("pageshow", (event) => {
  if (event.persisted && !navigator.onLine) location.reload()
})
