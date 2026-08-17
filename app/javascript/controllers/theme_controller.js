import { Controller } from "@hotwired/stimulus"

// The manual light/dark override. The cookie is written client-side and read
// server-side (ApplicationHelper#theme_html_class), so the next navigation is
// already painted correctly. Flipping the <html> class here recolors the
// current page with no server round-trip — which is what keeps the toggle
// working offline without ever risking a stale figure (it touches chrome only).
export default class extends Controller {
  toggle() {
    const root = document.documentElement
    const next = root.classList.contains("dark") ? "light" : "dark"
    root.classList.remove("dark", "light")
    root.classList.add(next)
    document.cookie = `theme=${next}; path=/; max-age=31536000; samesite=lax`
    this.syncThemeColor(next)
    document.dispatchEvent(new CustomEvent("theme:change", { detail: { theme: next } }))
  }

  // Keep the address-bar / status-bar chrome in step with the manual choice;
  // the media-scoped metas only track the device, not the override.
  syncThemeColor(theme) {
    const color = theme === "dark" ? "#0b0f14" : "#f8fafc"
    document.querySelectorAll('meta[name="theme-color"]').forEach((m) => m.setAttribute("content", color))
  }
}
