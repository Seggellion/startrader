import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchInput"]

  connect() {
    this.timeout = null
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  queueSubmit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submitNow(), 300)
  }

  submitNow() {
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }
}
