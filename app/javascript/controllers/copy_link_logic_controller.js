import { Controller } from "@hotwired/stimulus"

// Copying the share link, and saying so.
//
// The clipboard is one of the few things only the browser can do, which is the
// test CLAUDE.md sets for reaching for Stimulus at all.
//
// The link is also sitting in a real, selectable input next to this button, so
// if the clipboard is blocked — an insecure origin, a permission refused, an
// older browser — the link can still be copied by hand. This controller is a
// convenience on top of something that already works.
export default class extends Controller {
  static targets = [ "link", "confirmation" ]

  async copy() {
    this.linkTarget.select()

    if (await this.#copied()) {
      this.confirmationTarget.hidden = false
    } else {
      // Never claim a copy that did not happen. The text is selected, so
      // the next thing to try is the keyboard.
      this.confirmationTarget.textContent = "Press ⌘C or Ctrl+C to copy."
      this.confirmationTarget.hidden = false
    }
  }

  // Selecting on focus means tapping the field is enough to copy by hand.
  selectAll() {
    this.linkTarget.select()
  }

  async #copied() {
    try {
      await navigator.clipboard.writeText(this.linkTarget.value)
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
