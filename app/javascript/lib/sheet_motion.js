const viewportCleanups = new WeakMap()
const sheetAnimations = new WeakMap()
const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

export function openSheet(dialog, {onDismiss} = {}) {
  dialog.classList.remove("is-closing")
  const surface = dialog.querySelector(".sheet-content")
  const viewport = window.visualViewport
  const fit = () => {
    dialog.style.setProperty("--sheet-height", `${viewport?.height || window.innerHeight}px`)
    dialog.style.setProperty("--sheet-keyboard", `${Math.max(0, window.innerHeight - (viewport?.height || window.innerHeight) - (viewport?.offsetTop || 0))}px`)
  }
  fit()
  viewport?.addEventListener("resize", fit)
  viewport?.addEventListener("scroll", fit)
  viewportCleanups.set(dialog, () => {
    viewport?.removeEventListener("resize", fit)
    viewport?.removeEventListener("scroll", fit)
  })
  // A gesture must start and finish outside. Dragging out of a field or a
  // keypad key must not accidentally dismiss the editor.
  let beganInside = false
  // Use the original event path: selecting a contact removes its result
  // button before the click reaches this listener. It is still an inside tap.
  const outside = event => !event.composedPath().includes(surface)
  const pointerDown = event => { beganInside = !outside(event) }
  const pointerCancel = () => { beganInside = false }
  const backdropClick = event => {
    if (!beganInside && outside(event)) {
      event.preventDefault()
      event.stopPropagation()
      onDismiss?.()
    }
    beganInside = false
  }
  dialog.addEventListener("pointerdown", pointerDown)
  dialog.addEventListener("pointercancel", pointerCancel)
  dialog.addEventListener("click", backdropClick)
  dialog.addEventListener("close", () => {
    dialog.removeEventListener("pointerdown", pointerDown)
    dialog.removeEventListener("pointercancel", pointerCancel)
    dialog.removeEventListener("click", backdropClick)
    viewportCleanups.get(dialog)?.()
    viewportCleanups.delete(dialog)
  }, {once: true})
  dialog.showModal()
  const focus = dialog.matches("[data-sheet-focus]") ? dialog : dialog.querySelector("[data-sheet-focus]")
  focus?.focus({preventScroll: true})
  if (!reducedMotion()) {
    sheetAnimations.set(dialog, surface.animate(
      [{opacity: 0, transform: "translateY(36px)"}, {opacity: 1, transform: "translateY(0)"}],
      {duration: 280, easing: "cubic-bezier(.22, 1, .36, 1)"}))
  }
}

export async function closeSheet(dialog) {
  if (!dialog.open || dialog.classList.contains("is-closing")) return
  dialog.classList.add("is-closing")
  const surface = dialog.querySelector(".sheet-content")
  const current = getComputedStyle(surface)
  const start = {opacity: current.opacity, transform: current.transform}
  sheetAnimations.get(dialog)?.cancel()
  let animation
  if (!reducedMotion()) {
    animation = surface.animate([start, {opacity: 0, transform: "translateY(24px)"}],
      {duration: 170, easing: "cubic-bezier(.4, 0, 1, 1)", fill: "forwards"})
    sheetAnimations.set(dialog, animation)
    await animation.finished.catch(() => {})
  }
  dialog.close()
  animation?.cancel()
  sheetAnimations.delete(dialog)
  dialog.classList.remove("is-closing")
}
