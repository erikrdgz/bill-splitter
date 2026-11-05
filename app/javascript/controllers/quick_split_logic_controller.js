import { Controller } from "@hotwired/stimulus"

// Mirrors SplitMath rules 2 and 6 in the browser, and nothing else.
//
// The spec is explicit that this is for instant feedback only: nothing here is
// saved, and SplitsController recomputes every amount with SplitMath when the
// split is created. If the two ever disagree, the server wins.
//
// The limits arrive as Stimulus values from SplitsController#new, so "2 to 20
// people" and the maximum total are written down once, in Ruby, and never
// duplicated here.
export default class extends Controller {
  static targets = [
    "amount",
    "peopleCount",
    "decrement",
    "increment",
    "shares",
    "shareRowTemplate",
    "centNote"
  ]

  static values = {
    minimumPeople: Number,
    maximumPeople: Number,
    maximumTotalCents: Number
  }

  connect() {
    this.recalculate()
  }

  recalculate() {
    const peopleCount = this.#peopleCount()
    const totalCents = this.#amountInCents()

    this.#renderRows(peopleCount, totalCents)
    this.#renderCentNote(peopleCount, totalCents)
    this.#updateStepperButtons(peopleCount)
  }

  decrement() {
    this.#stepPeopleCountBy(-1)
  }

  increment() {
    this.#stepPeopleCountBy(1)
  }

  // Typing is allowed to be mid-thought: someone reaching for 12 types "1"
  // first, and snapping that straight up to the minimum of 2 would fight them.
  // So the shares use the clamped count immediately, but the field itself is
  // only corrected once they commit the value, on change.
  normalizePeopleCount() {
    this.peopleCountTarget.value = this.#peopleCount()
    this.recalculate()
  }

  #stepPeopleCountBy(step) {
    this.peopleCountTarget.value = this.#clamped(this.#peopleCount() + step)
    this.recalculate()
  }

  #peopleCount() {
    return this.#clamped(parseInt(this.peopleCountTarget.value, 10))
  }

  #clamped(peopleCount) {
    if (Number.isNaN(peopleCount)) return this.minimumPeopleValue

    return Math.min(Math.max(peopleCount, this.minimumPeopleValue), this.maximumPeopleValue)
  }

  // Dollars typed as text into whole cents, without ever creating a float: a
  // float cannot hold 0.01 exactly, and this number is about to be divided.
  // Returns null when there is no amount yet.
  #amountInCents() {
    const digitsAndDot = this.amountTarget.value.replace(/[^0-9.]/g, "")
    if (digitsAndDot === "") return null

    const [ wholeDollars, fraction = "" ] = digitsAndDot.split(".")
    const dollarCents = (parseInt(wholeDollars, 10) || 0) * 100
    const fractionCents = parseInt(`${fraction}00`.slice(0, 2), 10) || 0
    const totalCents = Math.min(dollarCents + fractionCents, this.maximumTotalCentsValue)

    return totalCents === 0 ? null : totalCents
  }

  // Rule 2, the same arithmetic as SplitMath.even_shares: round down, then give
  // the leftover cents one each to the first rows in order.
  #evenShares(totalCents, peopleCount) {
    const baseShare = Math.floor(totalCents / peopleCount)
    const leftoverCents = totalCents - baseShare * peopleCount

    return Array.from({ length: peopleCount }, (_, index) =>
      index < leftoverCents ? baseShare + 1 : baseShare
    )
  }

  #renderRows(peopleCount, totalCents) {
    this.#matchRowCount(peopleCount)

    const shares = totalCents === null ? null : this.#evenShares(totalCents, peopleCount)

    this.#rows().forEach((row, index) => {
      row.querySelector("[data-share-row-name]").textContent = `Person ${index + 1}`
      row.querySelector("[data-share-row-amount]").textContent =
        shares === null ? "—" : this.#formattedDollars(shares[index])
    })
  }

  // Adds and drops only the rows that changed, rather than rebuilding the list,
  // so the aria-live region does not re-announce every row on every keystroke.
  #matchRowCount(peopleCount) {
    for (let index = this.#rows().length; index < peopleCount; index++) {
      this.sharesTarget.append(this.shareRowTemplateTarget.content.cloneNode(true))
    }

    this.#rows().slice(peopleCount).forEach((row) => row.remove())
  }

  #rows() {
    return Array.from(this.sharesTarget.children)
  }

  #renderCentNote(peopleCount, totalCents) {
    const leftoverCents = totalCents === null ? 0 : totalCents % peopleCount

    this.centNoteTarget.hidden = leftoverCents === 0
    if (leftoverCents === 0) return

    const whoPays = leftoverCents === 1
      ? "Person 1 pays"
      : `The first ${leftoverCents} people each pay`

    this.centNoteTarget.textContent =
      `${whoPays} one cent more, so the shares add up to ${this.#formattedDollars(totalCents)}.`
  }

  #updateStepperButtons(peopleCount) {
    this.decrementTarget.disabled = peopleCount <= this.minimumPeopleValue
    this.incrementTarget.disabled = peopleCount >= this.maximumPeopleValue
  }

  // Formatted straight from the integer, so no float ever touches the money.
  #formattedDollars(cents) {
    const dollars = Math.floor(cents / 100).toLocaleString("en-US")
    const remainder = String(cents % 100).padStart(2, "0")

    return `$${dollars}.${remainder}`
  }
}
