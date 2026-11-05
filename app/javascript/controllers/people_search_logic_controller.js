import { Controller } from "@hotwired/stimulus"

// Debounces the people search, and nothing else.
//
// The searching, the matching and the rendering are all the server's — this
// controller exists only because the browser knows something the server cannot:
// that the organizer is still typing. Submitting on every keystroke would send
// a request per letter and let a slow one answer after a fast one, so the list
// would flicker and could settle on the wrong query.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  search() {
    clearTimeout(this.timeout)

    // requestSubmit, not submit: it fires the submit event, which is how Turbo
    // knows to take the response into the frame rather than the whole page.
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  // A pending search after the frame has gone would submit a form that is no
  // longer on the page.
  disconnect() {
    clearTimeout(this.timeout)
  }
}
