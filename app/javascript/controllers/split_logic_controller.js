import { Controller } from "@hotwired/stimulus"

// The custom-split sliders.
//
// Mirrors SplitMath rules 3, 4 and 5 so the untouched rows move while a slider
// is being dragged — the one thing a round trip per pixel could never do. On
// release the form is submitted and SplitsController recomputes every amount
// with the real SplitMath, so whatever this controller got up to during the
// drag is replaced by the server's answer a moment later.
//
// Everything here is whole cents. The slider's own min, max, step and value are
// in cents too, so the browser never rounds money on our behalf.
export default class extends Controller {
  static targets = [ "row", "slider", "lock", "amount", "percentage", "form" ]
  static values = { totalCents: Number }

  connect() {
    if (this.hasSliderTarget) this.#render()
  }

  // Rule 3: touching a row locks it. The organizer has said what this person
  // pays, so the arithmetic stops deciding for them.
  drag(event) {
    const index = this.sliderTargets.indexOf(event.target)
    this.lockTargets[index].checked = true

    this.#respread()
  }

  // Tapping the lock frees a row back into the pool.
  toggleLock() {
    this.#respread()
  }

  // On release. The server's version replaces the rows.
  save() {
    this.formTarget.requestSubmit()
  }

  #respread() {
    const lockedAmounts = this.sliderTargets.map((slider, index) =>
      this.lockTargets[index].checked ? Number(slider.value) : null
    )

    this.#customShares(lockedAmounts).forEach((cents, index) => {
      this.sliderTargets[index].value = cents
    })

    this.#render()
  }

  // The same arithmetic as SplitMath.custom_shares: locked rows keep their
  // amount, and what is left spreads evenly over the rest, never below zero.
  #customShares(lockedAmounts) {
    const unlockedCount = lockedAmounts.filter((amount) => amount === null).length
    if (unlockedCount === 0) return lockedAmounts

    const lockedTotal = lockedAmounts.reduce((sum, amount) => sum + (amount ?? 0), 0)
    const remainingCents = Math.max(this.totalCentsValue - lockedTotal, 0)
    const shares = this.#evenShares(remainingCents, unlockedCount)

    return lockedAmounts.map((amount) => amount ?? shares.shift())
  }

  #evenShares(totalCents, peopleCount) {
    const baseShare = Math.floor(totalCents / peopleCount)
    const leftoverCents = totalCents - baseShare * peopleCount

    return Array.from({ length: peopleCount }, (_, index) =>
      index < leftoverCents ? baseShare + 1 : baseShare
    )
  }

  #render() {
    const amounts = this.sliderTargets.map((slider) => Number(slider.value))
    const locks = this.lockTargets.map((lock) => lock.checked)
    const unlockedCount = locks.filter((locked) => !locked).length

    this.sliderTargets.forEach((slider, index) => {
      // Rule 4: a row can never claim cents another locked row already holds.
      const otherLockedTotal = amounts.reduce(
        (sum, amount, other) => sum + (other !== index && locks[other] ? amount : 0),
        0
      )
      slider.max = Math.max(this.totalCentsValue - otherLockedTotal, 0)

      // Rule 4 again: if this is the only unlocked row, its amount is whatever
      // is left over, so there is nothing to drag.
      slider.disabled = !locks[index] && unlockedCount === 1

      this.amountTargets[index].textContent = this.#formattedDollars(amounts[index])
      this.percentageTargets[index].textContent = `${this.#percentage(amounts[index])}%`
    })

    this.#renderRemaining(amounts)
  }

  #renderRemaining(amounts) {
    const claimed = amounts.reduce((sum, amount) => sum + amount, 0)
    const remaining = this.element.querySelector("#remaining .tabular-nums")

    if (remaining) remaining.textContent = this.#formattedDollars(this.totalCentsValue - claimed)
  }

  // Rule 5: display only, one decimal, worked out from cents.
  #percentage(cents) {
    if (this.totalCentsValue === 0) return "0.0"

    return ((cents * 100) / this.totalCentsValue).toFixed(1)
  }

  // Built from the integer, so no float touches money here either.
  #formattedDollars(cents) {
    const sign = cents < 0 ? "-" : ""
    const absolute = Math.abs(cents)
    const dollars = Math.floor(absolute / 100).toLocaleString("en-US")
    const remainder = String(absolute % 100).padStart(2, "0")

    return `${sign}$${dollars}.${remainder}`
  }
}
