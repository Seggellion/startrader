import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item", "count"]

  connect() {
    this.filter()
  }

  filter() {
    const query = this.hasInputTarget ? this.inputTarget.value.toLowerCase().trim() : ""
    const terms = query.split(/\s+/).filter(Boolean)
    let visibleCount = 0

    this.itemTargets.forEach((el) => {
      const searchableText = (el.dataset.searchText || el.dataset.name || el.textContent || "").toLowerCase()
      const matches = terms.every((term) => searchableText.includes(term))

      el.classList.toggle("hidden", !matches)
      if (matches) visibleCount += 1
    })

    this.updateCount(visibleCount)
    this.dispatch("updated", { detail: { visibleCount }, bubbles: true })
  }

  updateCount(visibleCount) {
    if (!this.hasCountTarget) return

    this.countTargets.forEach((target) => {
      target.textContent = visibleCount
    })
  }
}
