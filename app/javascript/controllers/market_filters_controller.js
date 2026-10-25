import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]

  connect() { this.dirty = false }

  markDraft() {
    this.dirty = true
    this.statusTarget.textContent = "Unapplied changes. Press Apply to update results."
  }

  changed(event) {
    this.markDraft()
    if (event.target.name === "star_system") {
      this.dispatch("system", { detail: { system: event.target.value } })
    }
  }

  restore(event) {
    const state = event.detail
    for (const key of ["q", "star_system", "commodity_id", "location_type", "trade_mode", "sort", "direction"]) {
      const input = this.element.elements.namedItem(key)
      if (input) input.value = state.filters[key] || ""
    }
    this.dirty = false
    this.statusTarget.textContent = "Filters are applied only when you press Apply."
    this.dispatch("restored", { detail: state })
  }

  apply() {
    this.dirty = false
    this.statusTarget.textContent = "Applying filters…"
  }
}
