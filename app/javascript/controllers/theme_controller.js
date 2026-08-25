import { Controller } from "@hotwired/stimulus"

// The manual light/dark override. The cookie is written client-side and read
// server-side (ApplicationHelper#theme_html_class), so the next navigation is
// already painted correctly. Flipping the <html> class here recolors the
// current page with no server round-trip — which is what keeps the toggle
// working offline without ever risking a stale figure (it touches chrome only).
export default class extends Controller {
  static targets = ["knob"]

  // Device-follow stamps no class on <html>, so the knob's starting side has to
  // come from the theme actually on screen, not the (possibly absent) class. The
  // server already renders the knob on the right side for an explicit theme, so
  // this is a no-op there; only device-follow needs to move it, and it does so
  // with the slide suppressed so a page switch never animates the knob (the flicker).
  connect() {
    this.render(this.currentTheme(), { animate: false })
  }

  toggle() {
    const next = this.currentTheme() === "dark" ? "light" : "dark"
    const root = document.documentElement
    root.classList.remove("dark", "light")
    root.classList.add(next)
    document.cookie = `theme=${next}; path=/; max-age=31536000; samesite=lax`
    this.syncThemeColor(next)
    this.render(next)
    document.dispatchEvent(new CustomEvent("theme:change", { detail: { theme: next } }))
  }

  // The theme currently on screen: an explicit override class wins; otherwise
  // CSS is following the device, so read that.
  currentTheme() {
    const root = document.documentElement
    if (root.classList.contains("dark")) return "dark"
    if (root.classList.contains("light")) return "light"
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }

  // Slide the knob to the side of the active theme (moon/right = dark). With
  // `animate: false` the move is applied with the CSS transition suppressed for
  // that frame, so positioning the knob on connect can never read as a slide.
  render(theme, { animate = true } = {}) {
    if (!this.hasKnobTarget) return
    const dark = theme === "dark"
    if (!animate) this.knobTarget.classList.add("transition-none")
    this.knobTarget.classList.toggle("translate-x-5", dark)
    this.knobTarget.classList.toggle("translate-x-0.5", !dark)
    this.element.setAttribute("aria-checked", dark ? "true" : "false")
    if (!animate) {
      // Force the position to take effect this frame, then restore the transition
      // so a later user toggle still animates.
      void this.knobTarget.offsetWidth
      this.knobTarget.classList.remove("transition-none")
    }
  }

  // Keep the address-bar / status-bar chrome in step with the manual choice;
  // the media-scoped metas only track the device, not the override.
  syncThemeColor(theme) {
    const color = theme === "dark" ? "#0b0f14" : "#f8fafc"
    document.querySelectorAll('meta[name="theme-color"]').forEach((m) => m.setAttribute("content", color))
  }
}
