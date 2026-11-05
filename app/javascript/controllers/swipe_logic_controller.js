import { Controller } from "@hotwired/stimulus"

// Native range inputs keep their horizontal gesture. Only dragging the card
// itself reveals deletion; vertical movement remains normal page scrolling.
export default class extends Controller {
  static targets = ["surface", "delete"]

  // A card held open is a question waiting for an answer. Left alone it closes
  // itself, so a stray swipe does not leave a delete button sitting there
  // looking like something is pending — and so the next tap on that row hits
  // the row rather than a control the organizer has forgotten about.
  //
  // A value rather than a constant so the tests can shorten it; waiting five
  // real seconds in a system test buys nothing.
  static values = { revealTimeout: { type: Number, default: 5000 } }

  start(event) {
    if (this.deleting || this.deleteTarget.disabled || event.button > 0 || event.target.closest("dialog, input, textarea, select, [data-swipe-logic-target=delete]")) return
    // A fresh drag answers the question itself.
    this.#cancelAutoClose()
    this.startX = event.clientX
    this.startY = event.clientY
    this.revealWidth = Math.min(112, Math.max(76, this.element.clientWidth * .25))
    this.offset = this.element.dataset.swipeOpen === "true" ? -this.revealWidth : 0
    this.distance = this.offset
    this.tracking = true
    this.dragging = false
    this.suppress = false
  }
  move(event) {
    if (!this.tracking) return
    const horizontal = event.clientX - this.startX
    const vertical = event.clientY - this.startY
    if (!this.dragging && Math.abs(vertical) > Math.abs(horizontal) && Math.abs(vertical) > 8) {
      this.tracking = false
      return
    }
    if (!this.dragging && Math.abs(horizontal) < 10) return
    if (!this.dragging) {
      this.element.setPointerCapture(event.pointerId)
      this.element.classList.add("is-swiping")
      this.dragging = true
    }
    event.preventDefault()
    this.distance = Math.min(0, Math.max(-this.element.clientWidth, this.offset + horizontal))
    this.deleteTarget.hidden = false
    this.deleteTarget.style.width = `${Math.max(56, -this.distance - 20)}px`
    this.element.dataset.swipeCommit = String(-this.distance >= this.element.clientWidth * .85)
    this.surfaceTarget.style.transform = `translateX(${this.distance}px)`
  }
  async finish() {
    if (!this.tracking) return
    this.tracking = false
    this.element.classList.remove("is-swiping")
    if (!this.dragging) return
    this.suppress = true
    if (-this.distance >= this.element.clientWidth * .85) {
      this.deleting = true
      this.deleteTarget.style.width = `${this.element.clientWidth - 20}px`
      await this.#exit()
      // A rejected saved deletion must restore the card. Keep the exit held
      // while Turbo responds so it cannot flash back before the list redraws.
      const form = this.deleteTarget.type === "submit" ? this.deleteTarget.form : null
      form?.addEventListener("turbo:submit-end", event => {
        if (!event.detail.success) this.#restore()
      }, {once: true})
      this.deleteTarget.click()
      if (!form) this.deleting = false
    } else if (this.distance < -this.element.clientWidth * .18) this.reveal()
    else this.close()
  }
  async #exit() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    this.element.classList.add("is-deleting")
    const height = this.element.getBoundingClientRect().height
    const gap = parseFloat(getComputedStyle(this.element.parentElement).rowGap) || 0
    this.exitAnimations = [
      // Fade the entire row before its height becomes a thin clipping strip.
      // Keep opacity held at zero until the DOM removal or server response.
      this.element.animate([{opacity: 1}, {opacity: 0}],
        {duration: 150, delay: 40, easing: "ease-out", fill: "forwards"}),
      this.surfaceTarget.animate([
        {transform: `translateX(${this.distance}px)`},
        {transform: `translateX(${-this.element.clientWidth}px)`, opacity: 0}
      ], {duration: 180, easing: "cubic-bezier(.22, 1, .36, 1)", fill: "forwards"}),
      this.deleteTarget.animate([
        {opacity: 1, transform: "translateY(-50%) scale(1)"},
        {opacity: 0, transform: "translateY(-50%) scale(.94)"}
      ], {duration: 240, delay: 60, easing: "ease-out", fill: "forwards"}),
      this.element.animate([
        {height: `${height}px`, minHeight: "0", marginBottom: "0px"},
        {height: "0px", minHeight: "0", marginBottom: `${-gap}px`}
      ], {duration: 280, delay: 120, easing: "cubic-bezier(.4, 0, .2, 1)", fill: "forwards"})
    ]
    await Promise.all(this.exitAnimations.map(animation => animation.finished.catch(() => {})))
  }
  #restore() {
    // Cancelling drops the exit's forwards-fill, so the row is already back at
    // full height and opacity. Fade it in from zero so the return reads as a
    // return rather than a pop, and let close() spring the surface back.
    this.exitAnimations?.forEach(animation => animation.cancel())
    this.exitAnimations = [
      this.element.animate([{opacity: 0}, {opacity: 1}],
        {duration: 150, easing: "ease-out"})
    ]
    this.element.classList.remove("is-deleting")
    this.deleting = false
    this.close()
  }
  disconnect() {
    this.exitAnimations?.forEach(animation => animation.cancel())
    // Without this a pending timer wakes up holding a card that has left the page.
    this.#cancelAutoClose()
  }

  #startAutoClose() {
    this.#cancelAutoClose()
    if (this.revealTimeoutValue <= 0) return

    this.autoCloseTimer = setTimeout(() => {
      // Never shut under a keyboard user: ArrowLeft reveals and then focuses
      // the delete button, and pulling it out from under them would move focus
      // mid-decision. Wait again instead, and close once they move on.
      if (this.element.contains(document.activeElement)) return this.#startAutoClose()

      this.close()
    }, this.revealTimeoutValue)
  }

  #cancelAutoClose() {
    clearTimeout(this.autoCloseTimer)
    this.autoCloseTimer = null
  }

  cancel() {
    this.tracking = false
    this.element.classList.remove("is-swiping")
    this.close()
  }
  reveal() {
    this.element.dataset.swipeOpen = "true"
    this.deleteTarget.hidden = false
    this.element.dataset.swipeCommit = "false"
    this.deleteTarget.style.width = "56px"
    const width = Math.min(112, Math.max(76, this.element.clientWidth * .25))
    this.surfaceTarget.style.transform = `translateX(${-width}px)`
    this.#startAutoClose()
  }
  close() {
    this.#cancelAutoClose()
    this.element.dataset.swipeOpen = "false"
    this.element.dataset.swipeCommit = "false"
    this.surfaceTarget.style.transform = ""
    this.deleteTarget.hidden = true
    this.deleteTarget.style.width = "56px"
  }
  key(event) {
    if (event.target !== this.element || this.deleteTarget.disabled) return
    if (event.key === "ArrowLeft") { event.preventDefault(); this.reveal(); this.deleteTarget.focus() }
    if (event.key === "Escape" || event.key === "ArrowRight") { event.preventDefault(); this.close() }
    if (event.key === "Delete" || event.key === "Backspace") {
      event.preventDefault()
      this.reveal()
      this.deleteTarget.click()
    }
  }
  click(event) {
    if (this.suppress && !event.target.closest("[data-swipe-logic-target=delete]")) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.suppress = false
    }
  }
}
