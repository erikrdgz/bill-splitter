import { Controller } from "@hotwired/stimulus"

// The custom-split sliders.
//
// Custom mode is hand allocation: dragging a row sets that row and nothing
// else. No other slider's value moves, and — just as important — no other
// slider's range moves either. A range input draws its thumb at value / max, so
// changing another row's max slides its thumb without changing a cent behind
// it, which looks exactly like the sliders are chained together.
//
// So every slider runs the whole bill, from zero to the total, fixed. The
// amounts are free to come to less than the total (the organizer is covering
// the rest themselves) or more (they have overshot). The remaining figure says
// which, and the Save button stays shut until it reads zero — that is what
// keeps the total honest, not a cap on the sliders.
//
// Nothing here saves. SplitsController checks the posted amounts and refuses a
// split that does not add up, so the server still has the final say.
//
// Everything is whole cents. The slider's own min, max, step and value are in
// cents too, so the browser never rounds money on our behalf.
export default class extends Controller {
  static targets = [
    "row", "slider", "lock", "amount", "percentage",
    "remaining", "remainingLabel", "save", "spread"
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

  // Reads every slider and redraws what depends on them. It never writes a
  // slider's value or its range — only `spreadTheRest` moves a slider the
  // organizer did not touch, and only when they ask for it.
  #render() {
    const amounts = this.sliderTargets.map((slider) => Number(slider.value))
    const claimedCents = amounts.reduce((sum, amount) => sum + amount, 0)

    this.sliderTargets.forEach((_slider, index) => {
      this.amountTargets[index].textContent = this.#formattedDollars(amounts[index])
      this.percentageTargets[index].textContent = `${this.#percentage(amounts[index])}%`
    })

    this.#renderRemaining(this.totalCentsValue - claimedCents)
  }

  #renderRemaining(remainingCents) {
    const overshot = remainingCents < 0

    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = this.#formattedDollars(Math.abs(remainingCents))
    }

    if (this.hasRemainingLabelTarget) {
      this.remainingLabelTarget.textContent = overshot ? "Over by" : "Left to give"
    }

    // Saving a split that does not add up would only earn an error page, so the
    // button says what is wrong before it is pressed.
    if (this.hasSaveTarget) {
      this.saveTarget.disabled = remainingCents !== 0
      this.saveTarget.value = this.#saveLabel(remainingCents)
    }

    if (this.hasSpreadTarget) {
      this.spreadTarget.disabled = this.lockTargets.every((lock) => lock.checked)
    }
  }

  #saveLabel(remainingCents) {
    if (remainingCents === 0) return "Save amounts"
    if (remainingCents < 0) return `${this.#formattedDollars(-remainingCents)} over`

    return `${this.#formattedDollars(remainingCents)} left to give`
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
