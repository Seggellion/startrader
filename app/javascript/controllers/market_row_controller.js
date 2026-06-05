import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.classList.add("bg-cyan-400/10", "ring-1", "ring-cyan-300/40")
    this.timeout = setTimeout(() => {
      this.element.classList.remove("bg-cyan-400/10", "ring-1", "ring-cyan-300/40")
    }, 900)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
