import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "item"]

  connect() {
    this.key = null
    this.direction = "asc"
    this.element.addEventListener("search:updated", () => this.resort())
  }

  sort(event) {
    const key = event.params.key
    if (!key) return

    if (this.key === key) {
      this.direction = this.direction === "asc" ? "desc" : "asc"
    } else {
      this.key = key
      this.direction = "asc"
    }

    this.resort()
  }

  resort() {
    if (!this.key || !this.hasContainerTarget) return

    const visibleItems = this.itemTargets.filter((item) => !item.classList.contains("hidden"))
    const hiddenItems = this.itemTargets.filter((item) => item.classList.contains("hidden"))

    visibleItems.sort((a, b) => this.compare(a, b, this.key))
    if (this.direction === "desc") visibleItems.reverse()

    visibleItems.concat(hiddenItems).forEach((item) => this.containerTarget.appendChild(item))
  }

  compare(a, b, key) {
    const aValue = this.sortValue(a, key)
    const bValue = this.sortValue(b, key)
    const aNumber = Number(aValue)
    const bNumber = Number(bValue)

    if (aValue !== "" && bValue !== "" && Number.isFinite(aNumber) && Number.isFinite(bNumber)) {
      return aNumber - bNumber
    }

    return aValue.localeCompare(bValue, undefined, { numeric: true, sensitivity: "base" })
  }

  sortValue(item, key) {
    return (item.getAttribute(`data-sort-${key}`) || "").toString().trim().toLowerCase()
  }
}
