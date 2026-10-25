import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "snapshot"]
  static values = { grouped: Boolean, applied: Object, url: String }

  connect() {
    this.connected = true
    this.sequence = 0
    this.lastStarted = 0
    this.dirty = false
    this.forcePending = false
    this.loaded()
  }

  loaded() {
    this.navigation = false
    this.dirty = false
    if (this.hasSnapshotTarget) {
      this.appliedValue = JSON.parse(this.snapshotTarget.dataset.state)
      this.urlValue = this.snapshotTarget.dataset.url
    }
    this.dispatch("restore", { detail: this.appliedValue })
  }

  disconnect() {
    this.connected = false
    this.navigating()
  }

  navigating(event) {
    if (event?.type === "turbo:before-fetch-request" && event.target !== this.element) return
    this.navigation = true
    this.sequence++
    this.request?.abort()
    clearTimeout(this.timer)
  }

  stream(event) {
    if (!this.groupedValue) return
    const stream = event.target
    if (stream.getAttribute("action") !== "replace") return
    const match = /^market_row_production_facility_([0-9]+)$/.exec(stream.getAttribute("target") || "")
    if (!match) return
    const row = stream.querySelector("template")?.content.querySelector("article[data-terminal-api-id]")
    const selected = String(this.appliedValue.filters.terminal_api_id)
    const loadedHere = this.element.querySelector('[data-facility-id="' + match[1] + '"]')
    if (row?.dataset.terminalApiId !== selected && !loadedHere) return
    // Only known, applicable market-row replacements are suppressed.
    event.preventDefault()
    this.dirty = true
    this.showStatus("Updates available. Refresh results when ready.")
    this.schedule()
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
  }

  schedule() {
    if (!this.groupedValue || !this.connected || this.navigation || !this.dirty || this.request) return
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(this.forcePending), Math.max(0, 1000 - (Date.now() - this.lastStarted)) + 10)
  }

  refresh(event) {
    event?.preventDefault()
    this.dirty = true
    this.forcePending = true
    clearTimeout(this.timer)
    this.load(true)
  }

  interacting() {
    const focused = document.activeElement
    return focused && (focused.closest('[data-controller~="market-filters"]') ||
      (this.element.contains(focused) && focused.matches("a,button,input,select,textarea")))
  }

  async load(force) {
    if (!this.connected || this.navigation || this.request || !this.dirty) return
    if (!force && this.interacting()) return
    if (Date.now() - this.lastStarted < 1000) { this.schedule(); return }
    this.dirty = false
    this.forcePending = false
    this.lastStarted = Date.now()
    const sequence = ++this.sequence
    const request = new AbortController()
    this.request = request
    const scroll = { x: window.scrollX, y: window.scrollY }
    const focusId = this.element.contains(document.activeElement) ? document.activeElement.id : null
    this.showStatus("Refreshing applied results…")
    try {
      const response = await fetch(this.urlValue, { signal: request.signal, headers: { "Turbo-Frame": "market_results", Accept: "text/html" } })
      const html = await response.text()
      if (!this.connected || this.navigation || sequence !== this.sequence) return
      if (!response.ok) throw new Error("Market unavailable")
      const next = new DOMParser().parseFromString(html, "text/html").querySelector("turbo-frame#market_results")
      if (!next) throw new Error("Missing market frame")
      this.appliedValue = JSON.parse(next.dataset.marketResultsAppliedValue)
      this.urlValue = next.dataset.marketResultsUrlValue
      // Keep the controller element: automatic refresh must not restore/discard drafts.
      this.element.replaceChildren(...Array.from(next.childNodes).map(node => document.importNode(node, true)))
      window.history.replaceState(window.history.state, "", this.urlValue)
      requestAnimationFrame(() => {
        if (!this.connected || sequence !== this.sequence) return
        if (focusId) (document.getElementById(focusId) || document.getElementById("market_results_heading"))?.focus({ preventScroll: true })
        window.scrollTo(scroll.x, scroll.y)
      })
      if (this.dirty) this.showStatus("Updates available. Refresh results when ready.")
    } catch (error) {
      if (error.name !== "AbortError" && this.connected && sequence === this.sequence) {
        this.showStatus("Refresh failed. Existing results and draft filters are preserved. Try Refresh results again.")
        // No automatic retry loop on network errors.
        this.dirty = false
      }
    } finally {
      if (this.request === request) this.request = null
      if (this.dirty) this.schedule()
    }
  }
}
