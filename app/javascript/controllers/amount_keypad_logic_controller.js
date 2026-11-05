import { Controller } from "@hotwired/stimulus"
import { openSheet, closeSheet } from "sheet_motion"

// Totals preview in the existing bill element. Person amounts stay isolated
// until confirmed, with their name and amount above the touch controls.
export default class extends Controller {
  static targets = ["field", "dialog", "display", "error", "context", "panel"]
  static values = { inline: { type: Boolean, default: false }, person: { type: Boolean, default: false } }

  connect() {
    this.#fitAmount()
    if (this.inlineValue) this.draft = this.fieldTarget.value.replace(/\.00$/, "") || "0"
  }
  sync() { this.#fitAmount() }
  open() {
    if (this.inlineValue && this.element.dataset.locked === "true") return
    this.dispatch("prepare")
    this.original = this.fieldTarget.value
    this.draft = this.original.replace(/[^0-9.]/g, "").replace(/\.00$/, "") || "0"
    this.errorTarget.hidden = true
    if (this.personValue) {
      this.contextTarget.textContent = this.fieldTarget.dataset.personName
      this.dialogTarget.setAttribute("aria-label", `Amount for ${this.fieldTarget.dataset.personName}`)
    }
    this.#render(false)
    if (this.inlineValue) {
      this.panelTarget.hidden = false
      this.dispatch("editing")
    } else openSheet(this.dialogTarget, {onDismiss: () => this.close()})
  }
  openKey(event) {
    if (event.key === "Enter" || event.key === " ") { event.preventDefault(); this.open() }
  }
  close() {
    if (!this.personValue) this.#write(this.original)
    closeSheet(this.dialogTarget)
  }
  cancel(event) { event.preventDefault(); this.close() }
  press(event) { this.#append(event.currentTarget.dataset.key) }
  clear() { this.draft = "0"; this.errorTarget.hidden = true; this.#render() }
  erase() { this.draft = this.draft.slice(0, -1) || "0"; this.errorTarget.hidden = true; this.#render() }
  key(event) {
    if (this.inlineValue && this.element.dataset.locked === "true") return
    // Enter on a focused keypad button should activate that button normally.
    if (event.key === "Enter" && event.target.tagName === "BUTTON") return
    if (/^[0-9.]$/.test(event.key)) { event.preventDefault(); this.#append(event.key) }
    if (event.key === "Backspace" || event.key === "Delete") { event.preventDefault(); this.erase() }
    if (event.key === "Enter") {
      event.preventDefault()
      if (this.inlineValue && this.element.dataset.updating !== "true") this.dispatch("continue")
      else this.apply()
    }
  }
  async apply() {
    if (this.applying) return
    const [whole, fraction = ""] = this.draft.split(".")
    const cents = Number(whole) * 100 + Number(`${fraction}00`.slice(0, 2))
    const maximum = Number(this.fieldTarget.dataset.maxCents || 9999999)
    if ((!this.personValue && cents < 1) || cents > maximum) {
      this.errorTarget.textContent = cents > maximum ? `Available: $${(maximum / 100).toLocaleString("en-US", {maximumFractionDigits: 2})}.` : "Enter an amount above zero."
      this.errorTarget.hidden = false
      return
    }
    const remainder = cents % 100
    this.#write(`${Math.floor(cents / 100)}${remainder ? `.${String(remainder).padStart(2, "0")}` : ""}`)
    if (this.inlineValue) {
      this.applying = true
      this.panelTarget.inert = true
      if (!matchMedia("(prefers-reduced-motion: reduce)").matches) {
        await this.panelTarget.animate([{ opacity: 1 }, { opacity: 0, transform: "translateY(6px)" }], { duration: 160, easing: "ease-out" }).finished
      }
      this.panelTarget.hidden = true
      this.panelTarget.inert = false
      this.applying = false
    } else closeSheet(this.dialogTarget)
    this.dispatch("apply", {detail: {cents}})
  }
  #write(value) {
    if (this.inlineValue) {
      this.panelTarget.hidden = false
      this.dispatch("editing")
    }
    this.fieldTarget.value = value
    this.#fitAmount()
    this.fieldTarget.dispatchEvent(new Event("input", {bubbles: true}))
    this.fieldTarget.dispatchEvent(new Event("change", {bubbles: true}))
  }
  #append(key) {
    if (key === "." && this.draft.includes(".")) return
    if (this.draft.includes(".") && this.draft.split(".")[1].length >= 2) return
    const next = this.draft === "0" && key !== "." ? key : this.draft + key
    if (Number(next) > 99999.99) {
      this.errorTarget.textContent = "Maximum $99,999.99."
      this.errorTarget.hidden = false
      return
    }
    this.draft = next
    this.errorTarget.hidden = true
    this.#render()
  }
  #render(preview = true) {
    const [whole, fraction] = this.draft.split(".")
    this.displayTarget.textContent = `$${Number(whole).toLocaleString("en-US")}${fraction !== undefined ? `.${fraction}` : ""}`
    this.displayTarget.dataset.long = String(this.draft.length > 7)
    if (preview && !this.personValue) this.#write(this.draft)
  }
  #fitAmount() {
    this.element.dataset.longAmount = String(this.fieldTarget.value.length > 7)
    this.fieldTarget.style.setProperty("--amount-characters", Math.max(1, this.fieldTarget.value.length))
  }
}
