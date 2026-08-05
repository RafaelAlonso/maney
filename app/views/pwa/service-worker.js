// Maney stores exactly one thing offline: a static page with no data on it.
// `install` is the only writer; `fetch` never caches a response. A figure that
// is no longer current therefore has no route into storage at all.
const CACHE = "maney-offline-v1"
const OFFLINE_URL = "/offline.html"

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll([OFFLINE_URL])))
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const request = event.request

  // Returning without calling respondWith leaves the request entirely to the
  // browser. Stylesheets, scripts and Turbo's fetches behave as they do today.
  //
  // POSTs are deliberately excluded: offering "tentar de novo" after a failed
  // save would imply the expense might have gone through, and reloading a POST
  // triggers a resubmission prompt. Capturing writes offline is w3's job.
  if (request.mode !== "navigate" || request.method !== "GET") return

  event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)))
})
