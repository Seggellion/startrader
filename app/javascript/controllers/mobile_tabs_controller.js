import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.showPanel("market")
  }

  show(event) {
    this.showPanel(event.params.panel)
  }

  showPanel(name) {
    this.tabTargets.forEach((tab) => {
      tab.dataset.active = String(tab.dataset.mobileTabsPanelParam === name)
    })

    this.panelTargets.forEach((panel) => {
      const isActive = panel.dataset.mobileTabsNameValue === name
      panel.classList.toggle("hidden", !isActive)
      panel.classList.toggle("block", isActive)
    })
  }
}
