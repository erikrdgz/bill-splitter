import { Controller } from "@hotwired/stimulus"
import { openSheet, closeSheet } from "sheet_motion"

// Totals preview in the existing bill element. Person amounts stay isolated
// until confirmed, with their name and amount above the touch controls.
export default class extends Controller {
  static targets = ["field", "dialog", "display", "error", "context"]
  static values = { person: { type: Boolean, default: false } }

  connect() { this.#fitAmount() }
  open() {
    this.dispatch("prepare")
    this.original = this.fieldTarget.value
    this.draft = this.original.replace(/[^0-9.]/g, "").replace(/\.00$/, "") || "0"
    this.errorTarget.hidden = true
    if (this.personValue) {
      this.contextTarget.textContent = this.fieldTarget.dataset.personName
      this.dialogTarget.setAttribute("aria-label", `Amount for ${this.fieldTarget.dataset.personName}`)
    }
    this.#render(false)
    openSheet(this.dialogTarget, {onDismiss: () => this.close()})
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
    if (/^[0-9.]$/.test(event.key)) { event.preventDefault(); this.#append(event.key) }
    if (event.key === "Backspace" || event.key === "Delete") { event.preventDefault(); this.erase() }
    if (event.key === "Enter") { event.preventDefault(); this.apply() }
  }
  apply() {
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
    this.dispatch("apply", {detail: {cents}})
    closeSheet(this.dialogTarget)
  }
  #write(value) {
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
