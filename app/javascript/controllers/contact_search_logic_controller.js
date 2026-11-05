import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "status"]
  static values = { url: String }

  disconnect() { this.reset() }
  reset() {
    clearTimeout(this.timer)
    this.request?.abort()
    this.resultsTarget.replaceChildren()
    this.resultsTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.statusTarget.textContent = ""
    this.options = []
    this.active = -1
  }
  search() {
    this.reset()
    this.dispatch("edit")
    const query = this.inputTarget.value.trim()
    if (!query) return
    this.timer = setTimeout(() => this.#load(query), 180)
  }
  async #load(query) {
    this.request = new AbortController()
    try {
      const url = new URL(this.urlValue, location.origin)
      url.searchParams.set("query", query)
      const response = await fetch(url, {signal: this.request.signal, headers: {Accept: "application/json"}})
      if (!response.ok) throw new Error("Contact search failed")
      const contacts = await response.json()
      if (this.inputTarget.value.trim() !== query) return
      contacts.forEach(contact => this.#option(contact.name, contact))
      if (!contacts.some(contact => contact.name.toLocaleLowerCase() === query.toLocaleLowerCase())) {
        this.#option(`Create contact “${query}”`, {id: "", name: query}, true)
      }
      this.resultsTarget.hidden = false
      this.inputTarget.setAttribute("aria-expanded", "true")
      this.statusTarget.textContent = contacts.length ? `${contacts.length} matching contacts` : "No matching contacts. Create a contact below."
    } catch (error) {
      if (error.name !== "AbortError") this.statusTarget.textContent = "Couldn’t load contacts. Type again to retry."
    }
  }
  #option(label, contact, create = false) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "contact-option"
    button.id = `contact-option-${this.options.length}`
    button.setAttribute("role", "option")
    button.setAttribute("aria-selected", "false")
    button.tabIndex = -1
    const avatar = document.createElement("span")
    avatar.className = `avatar avatar--small ${create ? "avatar--create" : `avatar--${contact.id % 5}`}`
    avatar.setAttribute("aria-hidden", "true")
    const words = contact.name.split(/\s+/)
    avatar.textContent = create ? "+" : [words[0], words.length > 1 ? words.at(-1) : ""].map(word => word[0] || "").join("").toUpperCase()
    const name = document.createElement("span")
    name.textContent = label
    button.append(avatar, name)
    button.addEventListener("click", () => {
      this.inputTarget.value = contact.name
      this.reset()
      this.inputTarget.blur()
      this.dispatch("select", {detail: contact})
    })
    this.options.push(button)
    this.resultsTarget.append(button)
  }
  leave(event) {
    if (!this.element.contains(event.relatedTarget)) this.reset()
  }
  key(event) {
    if (event.key === "Enter") event.preventDefault()
    if (this.resultsTarget.hidden) return
    if (["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault()
      this.active = (this.active + (event.key === "ArrowDown" ? 1 : -1) + this.options.length) % this.options.length
      this.options.forEach((button, index) => button.setAttribute("aria-selected", String(index === this.active)))
      this.inputTarget.setAttribute("aria-activedescendant", this.options[this.active].id)
      this.options[this.active].scrollIntoView({block: "nearest"})
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.options[Math.max(0, this.active)]?.click()
    } else if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.reset()
    }
  }
}
