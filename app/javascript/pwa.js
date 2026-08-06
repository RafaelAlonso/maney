if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker")
}

// The browser's bfcache restores a live page without any network request, so
// neither Turbo nor the service worker sees it. Reloading sends it through the
// worker, which answers with the no-connection screen when the server cannot be
// reached.
//
// The reload is unconditional on purpose. `navigator.onLine` only reports
// link-layer connectivity: it is true on a captive-portal wifi, on a network
// that needs a VPN, and any other time the phone has a connection but this
// self-hosted server does not answer — precisely the cases where a restored
// snapshot would put a full page of figures back on screen with no request for
// anything to intercept. For a money app, refusing to show an un-revalidated
// snapshot is the right default; the extra request when the server *is*
// reachable is a strictly smaller cost than the one this branch already
// accepts by disabling Turbo's snapshot cache app-wide.
addEventListener("pageshow", (event) => {
  if (event.persisted) location.reload()
})
