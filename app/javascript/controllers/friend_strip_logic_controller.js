import { Controller } from "@hotwired/stimulus"

// Show the edge hint only while there are more people in that direction.
export default class extends Controller {
  connect() {
    this.resizeObserver = new ResizeObserver(() => this.update())
    this.resizeObserver.observe(this.element)
    this.mutationObserver = new MutationObserver(() => this.update())
    this.mutationObserver.observe(this.element, { childList: true })
    this.update()
  }

  disconnect() {
    this.resizeObserver.disconnect()
    this.mutationObserver.disconnect()
  }

  update() {
    const end = this.element.scrollWidth - this.element.clientWidth
    this.element.dataset.moreLeft = String(this.element.scrollLeft > 2)
    this.element.dataset.moreRight = String(this.element.scrollLeft < end - 2)
  }
}
