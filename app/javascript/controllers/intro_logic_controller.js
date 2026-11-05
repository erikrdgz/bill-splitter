import { Controller } from "@hotwired/stimulus"

// The intro animates itself in CSS. The browser has to do nothing before the
// server can... except get the finished overlay out of the way, because an
// invisible full-screen layer is still a full-screen layer.
export default class extends Controller {
  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return this.element.remove()
    // Safety net: if the animation event never arrives (tab hidden mid-animation),
    // the overlay must still go away.
    this.fallback = setTimeout(() => this.element.remove(), 5000)
  }

  disconnect() { clearTimeout(this.fallback) }

  // animationend bubbles up from the logo's own animations; only the overlay's
  // fade-out means the intro is over.
  finish(event) {
    if (event.target === this.element) this.element.remove()
  }
}
