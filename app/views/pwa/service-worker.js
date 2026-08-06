// Maney stores exactly one thing offline: a static page with no data on it.
// `install` is the only writer; `fetch` never caches a response. A figure that
// is no longer current therefore has no route into storage at all.
const CACHE = "maney-offline-v1"
const OFFLINE_URL = "/offline.html"

self.addEventListener("install", (event) => {
  // `cache: "reload"` bypasses the HTTP cache for this one fetch. Production
  // serves everything in public/ with `max-age=31536000`, and addAll's default
  // cache mode would happily populate a freshly named cache from a year-old
  // stored copy — so editing offline.html and bumping CACHE would install a new
  // cache holding the *old* page, on exactly the devices that already have the
  // app. caches.match(OFFLINE_URL) still matches this entry: cache keys match
  // by URL, not by the Request object used to store them.
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll([ new Request(OFFLINE_URL, { cache: "reload" }) ]))
  )
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

  // This `fetch` inherits the navigation's cache mode, so keeping app HTML
  // fresh is the HTTP cache's job, not the worker's. It works today only
  // because Rails' default `must-revalidate` forbids serving a stored body
  // without asking the server: offline, revalidation fails, and we fall through
  // to the no-connection screen. Adding `expires_in` or `http_cache_forever` to
  // any screen with figures on it would let this line resolve straight from the
  // HTTP cache and serve stale money offline, with no test failing.
  //
  // `{cache: "no-store"}` is not the fix: it downgrades a `mode: "navigate"`
  // request to `same-origin` and breaks redirect handling.
  event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)))
})
