import { Controller } from "@hotwired/stimulus"

// The custom-split sliders.
//
// Custom mode is hand allocation: dragging a row sets that row and nothing
// else. No other slider's value moves, and — just as important — no other
// slider's range moves either. A range input draws its thumb at value / max, so
// changing another row's max slides its thumb without changing a cent behind
// it, which looks exactly like the sliders are chained together.
//
// So every slider runs the whole bill, from zero to the total, fixed, and only
// the row being dragged is ever written to. The bill is still a ceiling: a row
// is clamped to whatever no one else is holding, so the shares can never come
// to more than the total.
//
// They can come to less, and that is the point. $100 with $20 asked of one
// person and $30 of another leaves $50, and the $50 is what the organizer is
// paying themselves. The remaining figure says so, and the split saves.
//
// Nothing here saves. SplitsController checks the posted amounts, so the server
// still has the final say.
//
// Everything is whole cents. The slider's own min, max, step and value are in
// cents too, so the browser never rounds money on our behalf.
export default class extends Controller {
  static targets = [
    "row", "slider", "lock", "amount", "percentage",
    "remaining", "remainingLabel", "save", "spread", "add"
  ]

  static values = { totalCents: Number }

  connect() {
    if (this.hasSliderTarget) this.#render()
  }

  rowTargetConnected() { this.#refreshCountControls() }
  rowTargetDisconnected() { this.#refreshCountControls() }
  #refreshCountControls() {
    // Appending a custom row preserves existing unsaved inputs. Refresh only
    // controls whose availability depends on the new number of cards.
    this.rowTargets.forEach(row => {
      row.querySelector("[data-swipe-logic-target=delete]").disabled = this.rowTargets.length <= 1
    })
    if (this.hasAddTarget) this.addTarget.disabled = this.rowTargets.length >= 20
  }

  // Turbo morphs this controller in place after a rejected total change, so
  // connect() does not run again. Recompute the disabled state from the new bill.
  totalCentsValueChanged() {
    if (this.hasSliderTarget && this.hasRemainingTarget) this.#render()
  }

  // Touching a row locks it: the organizer has said what this person pays, so
  // "spread the rest evenly" leaves it alone from here on.
  //
  // The dragged row is clamped to what the others have not claimed. This is the
  // only slider written to, so no other thumb moves — the clamp that caused the
  // original bug was the one applied to every row's `max`, not this one.
  drag(event) {
    const index = this.sliderTargets.indexOf(event.target)
    const slider = this.sliderTargets[index]
    const heldByOthers = this.sliderTargets.reduce(
      (sum, other, position) => sum + (position === index ? 0 : Number(other.value)),
      0
    )
    const available = Math.max(this.totalCentsValue - heldByOthers, 0)

    slider.value = Math.min(Math.round(Number(slider.value) / 100) * 100, Math.floor(available / 100) * 100)

    this.lockTargets[index].checked = true

    this.#render()
  }

  stepShare(event) {
    if (!["ArrowLeft", "ArrowDown", "ArrowRight", "ArrowUp"].includes(event.key)) return
    event.preventDefault()
    const direction = ["ArrowLeft", "ArrowDown"].includes(event.key) ? -1 : 1
    event.target.value = (Math.round(Number(event.target.value) / 100) + direction) * 100
    this.drag(event)
  }

  prepareAmount(event) {
    const row = event.target.closest("[data-split-logic-target=row]")
    const index = this.rowTargets.indexOf(row)
    const field = event.target.querySelector("[data-amount-keypad-logic-target=field]")
    field.value = Number(this.sliderTargets[index].value) / 100
    field.dataset.personName = row.querySelector("[data-person-name]").textContent.trim()
    const others = this.sliderTargets.reduce((sum, slider, position) => sum + (position === index ? 0 : Number(slider.value)), 0)
    field.dataset.maxCents = Math.max(0, this.totalCentsValue - others)
  }

  setAmount(event) {
    const index = this.rowTargets.indexOf(event.target.closest("[data-split-logic-target=row]"))
    this.sliderTargets[index].value = event.detail.cents
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
    // Dragging cannot produce this, because a dragged row is clamped. Lowering
    // the total underneath amounts already set can, and the server refuses it,
    // so the screen says so rather than offering a button that will fail.
    const overshot = remainingCents < 0
    this.remainingTarget.closest("#remaining").dataset.over = String(overshot)

    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = this.#formattedDollars(Math.abs(remainingCents))
    }

    if (this.hasRemainingLabelTarget) {
      this.remainingLabelTarget.textContent = overshot ? "Over the bill by" : "You pay"
    }

    if (this.hasSaveTarget) {
      this.saveTarget.disabled = overshot
      this.saveTarget.value = overshot
        ? `${this.#formattedDollars(-remainingCents)} over the bill`
        : "Save amounts"
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
