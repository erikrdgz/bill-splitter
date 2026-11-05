import { Controller } from "@hotwired/stimulus"

// Bill details and people are two views of the same unsaved draft.
export default class extends Controller {
  static targets = ["title", "amount", "keypadController", "nextArea", "next", "group", "review", "edit", "updateKeypad", "updateAmount"]
  static values = { restored: Boolean }

  connect() {
    this.editingBill = false
    this.resize = () => this.#sizeGroup()
    window.addEventListener("resize", this.resize)
    window.visualViewport?.addEventListener("resize", this.resize)
    this.#showGroup(this.restoredValue && Number(this.amountTarget.value) > 0 && Boolean(this.titleTarget.value.trim()))
    this.validate()
  }

  disconnect() {
    window.removeEventListener("resize", this.resize)
    window.visualViewport?.removeEventListener("resize", this.resize)
  }

  #sizeGroup() {
    const top = this.element.getBoundingClientRect().top + window.scrollY
    const viewport = window.visualViewport?.height || window.innerHeight
    this.element.style.setProperty("--composer-height", `${Math.max(360, viewport - top)}px`)
  }

  validate() {
    this.nextTarget.disabled = !this.titleTarget.value.trim() || Number(this.amountTarget.value) <= 0
  }

  focusTitle() { this.titleTarget.focus({ preventScroll: true }) }

  titleNext(event) {
    event.preventDefault()
    if (this.element.dataset.stage === "group") {
      if (this.editingBill) this.edit()
      return
    }
    if (!this.nextTarget.disabled) this.advance()
    else this.amountTarget.focus({ preventScroll: true })
  }

  async advance() {
    if (this.transitioning) return
    this.validate()
    if (this.nextTarget.disabled) return
    this.titleTarget.value = this.titleTarget.value.trim()
    this.transitioning = true
    const panel = this.keypadControllerTarget.querySelector(".entry-keypad")
    if (!panel.hidden && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
      await panel.animate([{ opacity: 1 }, { opacity: 0, transform: "translateY(6px)" }], { duration: 160, easing: "ease-out" }).finished
    }
    this.#showGroup(true)
    this.transitioning = false
    this.#reveal(this.groupTarget)
    this.groupTarget.querySelector("h2").focus({ preventScroll: true })
    window.scrollTo({ top: 0, behavior: "instant" })
  }

  // Review is a third view of the same draft. data-stage stays "group" so the
  // bill header keeps its read-only look; data-review only swaps the panels.
  review() {
    if (this.editingBill) this.edit()
    this.#showReview(true)
    this.reviewTarget.querySelector("h2").focus({ preventScroll: true })
    window.scrollTo({ top: 0, behavior: "instant" })
  }

  backToGroup() {
    this.#showReview(false)
    this.groupTarget.querySelector("h2").focus({ preventScroll: true })
  }

  #showReview(reviewing) {
    this.element.dataset.review = String(reviewing)
    this.groupTarget.hidden = reviewing
    this.reviewTarget.hidden = !reviewing
    if (!reviewing) this.#reveal(this.groupTarget)
    else this.#reveal(this.reviewTarget)
  }

  edit() {
    if (this.editingBill && !this.titleTarget.value.trim()) { this.focusTitle(); return }
    this.editingBill = !this.editingBill
    this.element.dataset.editingBill = String(this.editingBill)
    this.titleTarget.readOnly = !this.editingBill
    this.titleTarget.tabIndex = this.amountTarget.tabIndex = this.editingBill ? 0 : -1
    this.editTarget.setAttribute("aria-label", this.editingBill ? "Done editing bill" : "Edit bill details")
    if (this.editingBill) this.focusTitle()
    else this.titleTarget.value = this.titleTarget.value.trim()
  }

  openAmount(event) {
    if (this.element.dataset.stage !== "group" || !this.editingBill) return
    event.preventDefault()
    this.updateAmountTarget.value = this.amountTarget.value
    this.application.getControllerForElementAndIdentifier(this.updateKeypadTarget, "amount-keypad-logic").open()
  }

  previewAmount() {
    this.amountTarget.value = this.updateAmountTarget.value
    this.application.getControllerForElementAndIdentifier(this.keypadControllerTarget, "amount-keypad-logic").sync()
    this.amountTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  submit(event) {
    if (this.element.dataset.stage === "group" && !this.titleTarget.value.trim()) {
      event.preventDefault()
      this.focusTitle()
      return
    }
    if (this.element.dataset.stage !== "group") {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.titleNext(event)
    }
  }

  #showGroup(group) {
    this.element.dataset.stage = group ? "group" : "details"
    if (group) this.#sizeGroup()
    this.groupTarget.hidden = !group
    this.reviewTarget.hidden = true
    this.element.dataset.review = "false"
    this.editTarget.hidden = !group
    this.nextAreaTarget.hidden = group
    this.titleTarget.readOnly = group
    this.titleTarget.tabIndex = group ? -1 : 0
    this.amountTarget.tabIndex = group ? -1 : 0
    this.keypadControllerTarget.dataset.locked = String(group)
    this.keypadControllerTarget.querySelector(".entry-keypad").hidden = group
  }

  #reveal(element) {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return
    // A transformed ancestor would temporarily reposition the fixed request bar.
    const frames = element === this.groupTarget ? [{ opacity: 0 }, { opacity: 1 }] :
      [{ opacity: 0, transform: "translateY(10px)" }, { opacity: 1, transform: "translateY(0)" }]
    element.animate(frames, { duration: 300, easing: "cubic-bezier(.22, 1, .36, 1)" })
  }
}
