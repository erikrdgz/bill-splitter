import { Controller } from "@hotwired/stimulus"

// The custom-split sliders.
//
// Custom mode is hand allocation: dragging a row sets that row and nothing
// else. Rows the organizer has not touched keep what they were last given,
// because re-evening them would undo the decision just made — drop one person
// to zero and the other two should stay where they are, with the freed money
// showing up as "left to give".
//
// Rule 4 is what keeps this honest: a slider's maximum is the total minus
// every other row, so the amounts can never add up to more than the bill. They
// can add up to less, and that gap is the remaining figure the organizer works
// down to zero before the Save button comes alive.
//
// Nothing here saves. SplitsController checks the posted amounts and refuses a
// split that does not add up, so the server still has the final say — it just
// says "no" rather than quietly rewriting the allocation.
//
// Everything is whole cents. The slider's own min, max, step and value are in
// cents too, so the browser never rounds money on our behalf.
export default class extends Controller {
  static targets = [
    "row", "slider", "lock", "amount", "percentage", "remaining", "save", "spread"
  ]

  static values = { totalCents: Number }

  connect() {
    if (this.hasSliderTarget) this.#render()
  }

  // Touching a row locks it: the organizer has said what this person pays, so
  // "spread the rest evenly" leaves it alone from here on.
  drag(event) {
    const index = this.sliderTargets.indexOf(event.target)
    this.lockTargets[index].checked = true

    this.#render()
  }

  toggleLock() {
    this.#render()
  }

  // Rule 2 over the rows nobody has set: each gets an equal share of whatever
  // the locked rows have left. This is the shortcut out of a fiddly allocation,
  // not something that happens behind the organizer's back.
  spreadTheRest() {
    const lockedAmounts = this.sliderTargets.map((slider, index) =>
      this.lockTargets[index].checked ? Number(slider.value) : null
    )

    this.#customShares(lockedAmounts).forEach((cents, index) => {
      this.sliderTargets[index].value = cents
    })

    this.#render()
  }

  // The same arithmetic as SplitMath.custom_shares.
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
    const claimedCents = amounts.reduce((sum, amount) => sum + amount, 0)
    const remainingCents = this.totalCentsValue - claimedCents

    this.sliderTargets.forEach((slider, index) => {
      // Rule 4: this row may take everything no other row is holding.
      slider.max = Math.max(this.totalCentsValue - (claimedCents - amounts[index]), 0)

      this.amountTargets[index].textContent = this.#formattedDollars(amounts[index])
      this.percentageTargets[index].textContent = `${this.#percentage(amounts[index])}%`
    })

    this.#renderRemaining(remainingCents)
  }

  #renderRemaining(remainingCents) {
    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = this.#formattedDollars(remainingCents)
    }

    // Saving a split that does not add up would only earn an error page, so the
    // button says so before it is pressed.
    if (this.hasSaveTarget) {
      this.saveTarget.disabled = remainingCents !== 0
      this.saveTarget.value = remainingCents === 0
        ? "Save amounts"
        : `${this.#formattedDollars(Math.abs(remainingCents))} left to give`
    }

    if (this.hasSpreadTarget) {
      this.spreadTarget.disabled = this.lockTargets.every((lock) => lock.checked)
    }
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
