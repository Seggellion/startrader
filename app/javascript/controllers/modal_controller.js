import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

connect(){
    console.log("Modal output");
}

  open(event) {
    event.preventDefault()
    this.dialogTarget.classList.remove("hidden")
  }

  close(event) {
    event.preventDefault()
    this.dialogTarget.classList.add("hidden")
  }
}