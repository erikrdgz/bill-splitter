import { Controller } from "@hotwired/stimulus"
import { openSheet, closeSheet } from "sheet_motion"
import { addPortrait } from "avatar_portrait"

// The calculator stays entirely local. Connecting prepares a row; only saving
// or reviewing requests submits the draft for server validation.
export default class extends Controller {
  static targets = ["amount", "peopleCount", "countDisplay", "add", "shares",
    "shareRowTemplate", "centNote", "friend", "remaining", "remainingLabel", "save", "request", "next", "connectNote",
    "reviewList", "reviewRemaining",
    "error", "dialog", "connectionName", "connectionPhone", "connectionAmount", "method",
    "handleFields", "connectionError", "comparison", "comparisonAmount", "comparisonLabel", "connectionPerson"]
  static values = { minimumPeople: Number, maximumPeople: Number, maximumTotalCents: Number, draft: Array }

  connect() {
    this.rows = this.draftValue.map(row => ({...row, amount_cents: Number(row.amount_cents), locked: row.locked === "1"}))
    this.custom = this.rows.length > 0
    this.recalculate()
  }

  recalculate() {
    const count = this.#count()
    while (this.rows.length < count) this.rows.push({amount_cents: 0, locked: false})
    this.rows = this.rows.slice(0, count)
    this.total = this.#cents(this.amountTarget.value)
    if (!this.custom) this.#distribute()
    this.#render()
  }

  increment() {
    this.#step(1)
    // Only the card bucket scrolls. Keep the new spot visible while Add and
    // the bill controls remain anchored in the mobile viewport.
    this.sharesTarget.scrollTo({ top: this.sharesTarget.scrollHeight, behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" })
  }
  #step(change) {
    this.peopleCountTarget.value = Math.min(this.maximumPeopleValue, Math.max(this.minimumPeopleValue, this.#count() + change))
    this.recalculate()
  }
  #count() {
    return Math.min(this.maximumPeopleValue, Math.max(this.minimumPeopleValue, parseInt(this.peopleCountTarget.value, 10) || this.minimumPeopleValue))
  }
  remove(event) {
    if (this.rows.length <= this.minimumPeopleValue) return
    this.rows.splice(this.#index(event), 1)
    // Remove the exiting card itself so its animation never carries over to
    // the next person when the remaining rows are rendered.
    event.target.closest("li").remove()
    this.peopleCountTarget.value = this.rows.length
    if (!this.rows.length) this.custom = false
    this.recalculate()
  }
  #index(event) { return Array.from(this.sharesTarget.children).indexOf(event.target.closest("li")) }

  #cents(value) {
    const text = value.replace(/[^0-9.]/g, "")
    const [whole, fraction = ""] = text.split(".")
    return Math.min((parseInt(whole, 10) || 0) * 100 + (parseInt(`${fraction}00`.slice(0, 2), 10) || 0), this.maximumTotalCentsValue)
  }
  #distribute() {
    if (!this.rows.length) return
    const base = Math.floor(this.total / this.rows.length)
    const remainder = this.total % this.rows.length
    this.rows.forEach((row, index) => { row.amount_cents = base + (index < remainder ? 1 : 0); row.locked = false })
  }
  splitEvenly() { this.custom = false; this.recalculate() }
  drag(event) { this.#setShare(this.#index(event), Math.round(Number(event.target.value) / 100) * 100, true) }
  stepShare(event) {
    if (!["ArrowLeft", "ArrowDown", "ArrowRight", "ArrowUp"].includes(event.key)) return
    event.preventDefault()
    const direction = ["ArrowLeft", "ArrowDown"].includes(event.key) ? -1 : 1
    this.#setShare(this.#index(event), (Math.round(Number(event.target.value) / 100) + direction) * 100, true)
  }
  setAmount(event) { this.#setShare(this.#index(event), event.detail.cents) }
  setPercentage(event) {
    const percent = Number(event.target.value)
    if (Number.isFinite(percent)) this.#setShare(this.#index(event), Math.round(this.total * Math.max(0, Math.min(100, percent)) / 100))
    else this.#render()
  }
  #setShare(index, cents, whole = false) {
    const held = this.rows.reduce((sum, row, position) => sum + (position === index ? 0 : row.amount_cents), 0)
    const available = Math.max(0, this.total - held)
    this.rows[index].amount_cents = Math.min(Math.max(0, cents), whole ? Math.floor(available / 100) * 100 : available)
    this.rows[index].locked = true
    this.custom = true
    this.#render()
  }

  chooseFriend(event) {
    const friend = event.currentTarget.dataset
    this.connectionNameTarget.value = friend.friendName
    this.dialogTarget.querySelector("[data-controller=contact-search-logic]").dispatchEvent(new Event("reset-contact-search"))
    this.selectContact({detail: {id: friend.personId, name: friend.friendName,
      portraitIndex: friend.portraitIndex, phoneNumber: friend.phoneNumber}})
  }
  openConnection(event) {
    this.connectionIndex = this.#index(event)
    const row = this.rows[this.connectionIndex]
    this.connectionNameTarget.value = row.name || ""
    this.connectionPersonId = row.person_id || ""
    this.connectionOriginalName = row.name || ""
    const friend = this.friendTargets.find(button => button.dataset.personId === String(row.person_id))
    this.connectionPhone = friend?.dataset.phoneNumber || ""
    this.connectionPortrait = row.portrait_index ?? friend?.dataset.portraitIndex
    this.methodTargets.forEach(input => { input.checked = input.value === (row.payment_method || "venmo") })
    this.connectionPersonTarget.textContent = row.name || `Person ${this.connectionIndex + 1}`
    this.connectionAmountTarget.textContent = this.#money(row.amount_cents)
    this.connectionErrorTarget.hidden = true
    this.changeMethod()
    if (row.phone_number) this.connectionPhoneTarget.value = row.phone_number
    this.dialogTarget.querySelector("[data-controller=contact-search-logic]").dispatchEvent(new Event("reset-contact-search"))
    this.#updateFriendChoices()
    openSheet(this.dialogTarget, {onDismiss: () => this.closeConnection()})
  }
  closeConnection(event) {
    event?.preventDefault()
    this.dialogTarget.querySelector("[data-controller=contact-search-logic]").dispatchEvent(new Event("reset-contact-search"))
    return closeSheet(this.dialogTarget)
  }
  connectionKey(event) {
    if (event.key === "Enter" && event.target === this.connectionPhoneTarget) {
      event.preventDefault()
      this.confirmConnection()
    }
  }
  editContact() {
    this.connectionPersonId = ""
    this.connectionPortrait = null
    this.connectionOriginalName = ""
    this.connectionPhone = ""
    this.connectionPhoneTarget.value = ""
    this.connectionErrorTarget.hidden = true
    this.#updateFriendChoices()
  }
  selectContact(event) {
    const contact = event.detail
    this.connectionPersonId = contact.id
    this.connectionPortrait = contact.portraitIndex
    this.connectionOriginalName = contact.name
    this.connectionPhone = contact.phoneNumber || ""
    this.connectionErrorTarget.hidden = true
    this.#updateFriendChoices()
    this.changeMethod()
  }
  #updateFriendChoices() {
    this.friendTargets.forEach(button => {
      const selected = String(this.connectionPersonId) === button.dataset.personId
      button.disabled = this.rows.some((row, index) => index !== this.connectionIndex && String(row.person_id) === button.dataset.personId)
      button.classList.toggle("is-connected", selected)
      button.setAttribute("aria-pressed", String(selected))
    })
  }
  changeMethod() {
    const method = this.methodTargets.find(input => input.checked).value
    // Cash is settled in person, so there is nobody to text.
    this.handleFieldsTarget.hidden = method === "cash"
    this.connectionPhoneTarget.value = this.connectionPhone || ""
  }
  async confirmConnection() {
    const name = this.connectionNameTarget.value.trim()
    const payment_method = this.methodTargets.find(input => input.checked).value
    const phone_number = payment_method === "cash" ? "" : this.connectionPhoneTarget.value.trim()
    if (name !== this.connectionOriginalName || !name) {
      this.connectionErrorTarget.textContent = "Choose a contact or create one from the search."
      this.connectionErrorTarget.hidden = false
      return
    }
    if (this.connectionPersonId && this.rows.some((row, index) => index !== this.connectionIndex && String(row.person_id) === String(this.connectionPersonId))) {
      this.connectionErrorTarget.textContent = "This contact is already in the split."
      this.connectionErrorTarget.hidden = false
      return
    }
    if (!name || (payment_method !== "cash" && !phone_number)) {
      this.connectionErrorTarget.textContent = !name ? "Enter a name." : "Enter a phone number."
      this.connectionErrorTarget.hidden = false
      return
    }
    Object.assign(this.rows[this.connectionIndex], {name, payment_method, phone_number, portrait_index: this.connectionPortrait,
      person_id: name === this.connectionOriginalName ? this.connectionPersonId : ""})
    await this.closeConnection()
    this.#render()
    this.sharesTarget.children[this.connectionIndex]?.scrollIntoView({ block: "nearest", behavior: "instant" })
  }
  prepareSubmit(event) {
    if (!this.rows.length || !this.total || this.total < this.rows.length || this.#remaining() < 0) {
      event.preventDefault()
      this.errorTarget.textContent = !this.rows.length ? "Add a person." : !this.total ? "Enter a bill amount." : this.#remaining() < 0 ? "The shares exceed the bill." : "Allow at least 1¢ per person."
      this.errorTarget.hidden = false
    }
  }
  #remaining() { return this.total - this.rows.reduce((sum, row) => sum + row.amount_cents, 0) }
  #money(cents) { return `$${Math.floor(cents / 100).toLocaleString("en-US")}${cents % 100 ? `.${String(cents % 100).padStart(2, "0")}` : ""}` }

  #render() {
    this.element.dataset.hasPeople = String(this.rows.length > 0)
    while (this.sharesTarget.children.length < this.rows.length) this.sharesTarget.append(this.shareRowTemplateTarget.content.cloneNode(true))
    Array.from(this.sharesTarget.children).slice(this.rows.length).forEach(element => element.remove())
    // One fixed scale for the whole draft, including a rejected lowered total.
    const maximum = Math.max(this.total, ...this.rows.map(row => row.amount_cents), 1)
    this.rows.forEach((row, index) => {
      const element = this.sharesTarget.children[index]
      const name = row.name || `Person ${index + 1}`
      element.querySelector("[data-share-row-name]").textContent = name
      const amount = element.querySelector("[data-share-row-amount]")
      amount.textContent = this.total ? this.#money(row.amount_cents) : "—"
      amount.setAttribute("aria-label", `Edit ${name}'s amount`)
      const amountField = element.querySelector("[data-share-amount-field]")
      amountField.value = row.amount_cents / 100
      amountField.dataset.personName = name
      amountField.dataset.maxCents = Math.max(0, this.#remaining() + row.amount_cents)
      element.querySelector("[data-share-row-connection]").textContent = row.payment_method ? {venmo:"Venmo", cash_app:"Cash App", cash:"Cash"}[row.payment_method] : "Connect"
      element.querySelector(".draft-connect").setAttribute("aria-label", `Connect ${name}`)
      element.querySelector(".draft-connect").dataset.connected = String(Boolean(row.name))
      const avatar = element.querySelector("[data-share-row-avatar]")
      avatar.hidden = !row.name
      const words = name.split(/\s+/)
      const tone = Array.from(name).reduce((sum, character) => sum + character.codePointAt(0), 0) % 5
      avatar.className = `avatar avatar--small ${row.name ? `avatar--${tone}` : "avatar--placeholder"}`
      avatar.textContent = row.name ? [words[0], words.length > 1 ? words.at(-1) : ""].map(word => word[0] || "").join("").toUpperCase() : index + 1
      const friend = this.friendTargets.find(button => button.dataset.personId === String(row.person_id))
      addPortrait(avatar, row.portrait_index ?? friend?.dataset.portraitIndex)
      const slider = element.querySelector("[data-share-row-slider]")
      slider.max = maximum
      slider.value = row.amount_cents
      slider.disabled = !this.total
      slider.setAttribute("aria-label", `${name}'s share`)
      slider.style.setProperty("--progress", `${row.amount_cents / maximum * 100}%`)
      const percent = element.querySelector("[data-share-row-percent]")
      percent.value = this.total ? (row.amount_cents * 100 / this.total).toFixed(1).replace(/\.0$/, "") : "0"
      percent.disabled = !this.total
      percent.setAttribute("aria-label", `${name}'s percentage`)
      const remove = element.querySelector(".swipe-delete")
      element.setAttribute("aria-label", `${name}. Swipe left or press Delete to remove.`)
      element.dataset.swipeOpen = "false"
      element.dataset.swipeCommit = "false"
      element.querySelector("[data-swipe-logic-target=surface]").style.transform = ""
      remove.hidden = true
      remove.style.width = "56px"
      remove.disabled = this.rows.length <= this.minimumPeopleValue
      remove.setAttribute("aria-label", `Remove ${name}`)
      element.querySelectorAll("[data-draft-field]").forEach(input => {
        input.value = input.dataset.draftField === "locked" ? (row.locked ? "1" : "0") : row[input.dataset.draftField] || (input.dataset.draftField === "amount_cents" ? "0" : "")
      })
    })
    const remaining = this.#remaining()
    this.remainingLabelTarget.textContent = remaining < 0 ? "Over the bill by" : "You pay"
    this.remainingTarget.textContent = this.total ? this.#money(Math.abs(remaining)) : "—"
    this.remainingTarget.parentElement.dataset.over = String(remaining < 0)
    this.countDisplayTarget.textContent = `${this.rows.length} ${this.rows.length === 1 ? "person" : "people"}`
    this.addTarget.disabled = this.rows.length >= this.maximumPeopleValue
    // Nobody can be asked for money until we know how they will pay, and cash
    // counts: an unconnected person simply needs to be set to cash.
    const everyoneConnected = this.rows.length > 0 && this.rows.every(row => row.payment_method)
    this.nextTarget.disabled = !everyoneConnected || remaining < 0 || !this.total
    this.connectNoteTarget.hidden = !this.rows.length || everyoneConnected
    this.saveTarget.disabled = this.requestTarget.disabled = this.nextTarget.disabled
    this.#renderReview(remaining)
    this.errorTarget.hidden = true
    this.centNoteTarget.hidden = !this.rows.length || this.custom || !this.total || this.total % this.rows.length === 0
    this.centNoteTarget.textContent = "Includes a 1¢ rounding adjustment."
    this.#renderComparison()
  }

  #renderReview(remaining) {
    const methods = {venmo: "Venmo", cash_app: "Cash App", cash: "Cash"}
    this.reviewListTarget.replaceChildren(...this.rows.map((row, index) => {
      const item = document.createElement("li")
      const who = document.createElement("span")
      const name = document.createElement("strong")
      name.textContent = row.name || `Person ${index + 1}`
      const method = document.createElement("small")
      method.textContent = methods[row.payment_method] || ""
      who.append(name, method)
      const amount = document.createElement("span")
      amount.textContent = this.#money(row.amount_cents)
      item.append(who, amount)
      return item
    }))
    this.reviewRemainingTarget.textContent = this.total ? this.#money(Math.abs(remaining)) : "—"
  }

  #renderComparison() {
    this.comparisonTarget.hidden = this.rows.length < 2 || !this.total
    if (this.comparisonTarget.hidden) return
    const amounts = this.rows.map(row => row.amount_cents)
    const minimum = Math.min(...amounts)
    const maximum = Math.max(...amounts)
    const roundedEven = !this.custom && minimum !== maximum
    this.comparisonAmountTarget.textContent = roundedEven ? `≈${this.#money(Math.round(this.total / this.rows.length))}` :
      minimum === maximum ? this.#money(minimum) : `${this.#money(minimum)}–${this.#money(maximum)}`
    this.comparisonLabelTarget.textContent = minimum === maximum || roundedEven ? "each" : "per person"
    this.comparisonTarget.dataset.range = String(minimum !== maximum && !roundedEven)
  }
}
