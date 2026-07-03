import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "selectedLocation",
    "selectedContext",
    "selectedCommodity",
    "selectedFacility",
    "selectedPlayerBuy",
    "selectedPlayerSell"
  ]

  selectRow(event) {
    if (event.target.closest("a")) return

    const row = event.currentTarget
    this.updateSelection(row)
  }

  focusLocation(event) {
    event.preventDefault()
    event.stopPropagation()

    const row = event.currentTarget.closest("[data-market-board-location-name-param]")
    this.updateSelection(row)

    window.dispatchEvent(new CustomEvent("star-trader:focus-location", {
      detail: this.selectionFrom(row)
    }))
  }

  updateSelection(row) {
    if (!row) return

    const selection = this.selectionFrom(row)
    this.setTargets(this.selectedLocationTargets, selection.locationName || "Unknown location")
    this.setTargets(this.selectedContextTargets, selection.context || "Uncharted")
    this.setTargets(this.selectedCommodityTargets, selection.commodityName || "-")
    this.setTargets(this.selectedFacilityTargets, selection.facilityName || "-")
    this.setTargets(this.selectedPlayerBuyTargets, this.formatPrice(selection.playerBuyPrice))
    this.setTargets(this.selectedPlayerSellTargets, this.formatPrice(selection.playerSellPrice))

    this.element.querySelectorAll("[data-market-board-location-name-param]").forEach((item) => {
      item.classList.toggle("bg-zinc-800/80", item === row)
    })
  }

  selectionFrom(row) {
    if (!row) return {}

    return {
      locationName: row.dataset.marketBoardLocationNameParam,
      facilityName: row.dataset.marketBoardFacilityNameParam,
      commodityName: row.dataset.marketBoardCommodityNameParam,
      systemName: row.dataset.marketBoardSystemNameParam,
      context: row.dataset.marketBoardContextParam,
      playerBuyPrice: row.dataset.marketBoardPlayerBuyPriceParam,
      playerSellPrice: row.dataset.marketBoardPlayerSellPriceParam
    }
  }

  setTargets(targets, value) {
    targets.forEach((target) => {
      target.textContent = value
    })
  }

  formatPrice(value) {
    const numeric = Number.parseFloat(value)
    if (!Number.isFinite(numeric) || numeric <= 0) return "-"

    return `aUEC ${numeric.toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }
}
