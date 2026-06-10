import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event.preventDefault()
    this.dialogTarget.classList.remove("hidden")
  }

  close(event) {
    event.preventDefault()
    this.dialogTarget.classList.add("hidden")
  }
}