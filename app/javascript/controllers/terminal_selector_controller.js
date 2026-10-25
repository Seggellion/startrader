import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "identity", "summary", "options", "status", "retry"]
  static values = { url: String, system: String }

  connect() {
    this.sequence = 0
    this.rows = []
    this.active = -1
    this.composing = false
    this.connected = true
  }

  disconnect() {
    this.connected = false
    this.invalidate()
    clearTimeout(this.blurTimer)
  }

  invalidate() {
    this.sequence++
    clearTimeout(this.timer)
    this.request?.abort()
    this.request = null
    this.rows = []
    this.active = -1
    this.optionsTarget.replaceChildren()
    this.close()
  }

  edited() {
    this.identityTarget.value = ""
    this.systemValue = ""
    this.summaryTarget.textContent = ""
    this.invalidate()
    this.retryTarget.hidden = true
    if (!this.composing) this.timer = setTimeout(() => this.search(), 275)
  }

  compositionStart() { this.composing = true; this.invalidate() }
  compositionEnd() { this.composing = false; this.edited() }
  focused() { if (this.rows.length) this.open() }
  blurred() { this.blurTimer = setTimeout(() => this.close(), 150) }

  async search() {
    this.invalidate()
    const query = this.inputTarget.value.trim()
    const system = this.currentSystem()
    if (query.length < 2) {
      this.statusTarget.textContent = "Type at least two characters to search."
      return
    }
    const sequence = this.sequence
    const request = new AbortController()
    this.request = request
    this.statusTarget.textContent = "Searching terminals…"
    this.retryTarget.hidden = true
    const params = new URLSearchParams({ q: query, star_system: system })
    try {
      const response = await fetch(this.urlValue + "?" + params, { signal: request.signal, headers: { Accept: "application/json" } })
      if (!this.current(sequence, query, system)) return
      const data = await response.json()
      if (!this.current(sequence, query, system)) return
      if (!response.ok || !Array.isArray(data.results)) throw new Error(data.error || "Terminal search unavailable")
      this.rows = data.results.slice(0, 20)
      this.renderOptions()
      this.statusTarget.textContent = this.rows.length ?
        String(this.rows.length) + " matches." + (data.has_more ? " Refine your search for more." : "") :
        "No matching market terminals. Refine the search or search all systems."
    } catch (error) {
      if (error.name === "AbortError" || !this.current(sequence, query, system)) return
      this.statusTarget.textContent = "Search failed. Your selection is unchanged. Retry search."
      this.retryTarget.hidden = false
    } finally {
      if (this.request === request) this.request = null
    }
  }

  current(sequence, query, system) {
    return this.connected && sequence === this.sequence &&
      query === this.inputTarget.value.trim() && system === this.currentSystem()
  }

  currentSystem() { return this.element.closest("form").elements.namedItem("star_system").value }

  renderOptions() {
    this.optionsTarget.replaceChildren()
    this.rows.forEach((row, index) => {
      const option = document.createElement("li")
      option.id = "market_terminal_option_" + row.terminal_api_id
      option.setAttribute("role", "option")
      option.setAttribute("aria-selected", "false")
      option.className = "cursor-pointer break-words border-b border-zinc-800 px-3 py-3 hover:bg-zinc-800"
      const name = document.createElement("span")
      name.className = "block font-semibold"
      name.textContent = row.name
      const context = document.createElement("span")
      context.className = "mt-1 block text-xs text-zinc-400"
      context.textContent = this.optionContext(row)
      option.append(name, context)
      option.addEventListener("mousedown", (event) => event.preventDefault())
      option.addEventListener("click", () => this.choose(index))
      this.optionsTarget.append(option)
    })
    if (this.rows.length && document.activeElement === this.inputTarget) this.open()
  }

  optionContext(row) {
    return [row.context, row.code, "ID " + row.terminal_api_id].filter(Boolean).join(" · ")
  }

  choose(index) {
    const row = this.rows[index]
    if (!row) return
    this.invalidate()
    this.inputTarget.value = row.name
    this.identityTarget.value = String(row.terminal_api_id)
    this.systemValue = row.star_system_name || ""
    this.summaryTarget.textContent = row.name + " · " + this.optionContext(row)
    this.statusTarget.textContent = "Selected " + row.name + ". Press Apply to update results."
    this.inputTarget.focus()
    this.dispatch("selected", { detail: { terminal: row } })
  }

  keyDown(event) {
    if (event.isComposing || this.composing) return
    if (["ArrowDown", "ArrowUp"].includes(event.key) && this.rows.length) {
      event.preventDefault()
      this.open()
      this.active = this.active < 0 ? (event.key === "ArrowDown" ? 0 : this.rows.length - 1) : (this.active + (event.key === "ArrowDown" ? 1 : -1) + this.rows.length) % this.rows.length
      Array.from(this.optionsTarget.children).forEach((option, index) => {
        option.setAttribute("aria-selected", String(index === this.active))
        option.classList.toggle("bg-zinc-800", index === this.active)
      })
      const option = this.optionsTarget.children[this.active]
      this.inputTarget.setAttribute("aria-activedescendant", option.id)
      option.scrollIntoView({ block: "nearest" })
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (!this.optionsTarget.hidden && this.rows.length) this.choose(this.active < 0 ? 0 : this.active)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    } else if (event.key === "Tab") {
      this.close()
    }
  }

  clear() {
    this.invalidate()
    this.identityTarget.value = ""
    this.inputTarget.value = ""
    this.summaryTarget.textContent = ""
    this.systemValue = ""
    this.statusTarget.textContent = "Terminal cleared. Press Apply to update results."
    this.inputTarget.focus()
    this.dispatch("selected", { detail: { terminal: null } })
  }

  restored(event) {
    this.invalidate()
    const state = event.detail
    this.identityTarget.value = state.filters.terminal_api_id || ""
    this.inputTarget.value = state.terminal_name || ""
    this.systemValue = state.terminal_system || ""
    this.summaryTarget.textContent = state.terminal_name ? state.terminal_name + " · " + state.terminal_context : (this.identityTarget.value ? "Unavailable selection — clear and choose a terminal." : "")
    this.statusTarget.textContent = "Type at least two characters to search. Apply commits your selection."
    this.retryTarget.hidden = true
  }

  systemChanged(event) {
    this.invalidate()
    if (this.identityTarget.value && event.detail.system && event.detail.system !== this.systemValue) {
      this.clear()
      this.statusTarget.textContent = "Terminal cleared because it is outside the selected system. Press Apply to update results."
    } else {
      this.statusTarget.textContent = "Search is now limited to " + (event.detail.system || "all systems") + "."
    }
  }

  allSystems() {
    const select = this.element.closest("form").elements.namedItem("star_system")
    select.value = ""
    select.dispatchEvent(new Event("change", { bubbles: true }))
    this.inputTarget.focus()
    this.search()
  }

  open() {
    this.optionsTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.optionsTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }
}
