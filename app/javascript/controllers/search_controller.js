import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item"]

connect(){
    console.log("Search output");
}

  filter() {
    const query = this.inputTarget.value.toLowerCase()

    this.itemTargets.forEach((el) => {
      const name = el.dataset.name || ""
      if (name.includes(query)) {
        el.classList.remove("hidden")
      } else {
        el.classList.add("hidden")
      }
    })
  }
}