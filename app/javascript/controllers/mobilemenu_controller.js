import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["menu", "submenu"]

    toggle() {

      this.menuTarget.classList.toggle("hidden")
    }

    toggleSubmenu(event) {
      event.preventDefault()
      const submenu = event.currentTarget.nextElementSibling
      if (submenu) {
        submenu.classList.toggle("hidden")
      }
    }

}
