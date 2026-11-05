import { Controller } from "@hotwired/stimulus"

// Copying text — a share link, or a whole batch of payment requests — and
// saying whether it worked.
//
// The clipboard is one of the few things only the browser can do, which is the
// test CLAUDE.md sets for reaching for Stimulus at all.
//
// The text is also sitting in a real, selectable field next to the button, so
// if the clipboard is blocked — an insecure origin, a permission refused, an
// older browser — it can still be copied by hand. This controller is a
// convenience on top of something that already works.
export default class extends Controller {
  static targets = [ "source", "confirmation" ]

  async copy() {
    this.sourceTarget.closest("details")?.setAttribute("open", "")
    this.sourceTarget.select()

    if (await this.#copied()) {
      this.confirmationTarget.textContent = this.confirmationTarget.dataset.copiedText || "Copied."
    } else {
      // Never claim a copy that did not happen. The text is selected, so
      // touch selection remains available on a phone.
      this.confirmationTarget.textContent = "Touch and hold the text to copy."
    }

    this.confirmationTarget.hidden = false
  }

  async share() {
    if (navigator.share) {
      try {
        await navigator.share({ text: this.sourceTarget.value })
        return
      } catch (error) {
        if (error.name === "AbortError") return
      }
    }
    await this.copy()
  }

  // Selecting on focus means tapping the field is enough to copy by hand.
  selectAll() {
    this.sourceTarget.select()
  }

  async #copied() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
      return true
    } catch {
      // Older browsers, and newer ones that refuse the permission.
      try {
        return document.execCommand("copy")
      } catch {
        return false
      }
    }
  }
}
