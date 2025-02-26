import { Controller } from "@hotwired/stimulus"
//import Sortable from "sortablejs";


export default class extends Controller {
  static targets = ["list"]

  async addPage(event) {
    if (event.target.checked) {
      const pageId = event.target.value
      const pageTitle = event.target.dataset.title
      const pageSlug = event.target.dataset.url

      const response = await fetch(`/admin/menus/${this.data.get("menuIdValue")}/menu_items`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        },
        body: JSON.stringify({ menu_item: { title: pageTitle, url: pageSlug, item_type: 'page', item_id: pageId } })
      })

      if (response.ok) {
        const contentType = response.headers.get("content-type")
        if (contentType && contentType.indexOf("application/json") !== -1) {
          const data = await response.json()
          const li = document.createElement("li")
          li.dataset.id = data.id

          li.innerHTML = `
            <div class="flex justify-between items-center">
              <span>${pageTitle}</span>
              <div>
                <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}/edit" class="btn btn-sm btn-secondary">Edit</a>
                <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}" data-method="delete" data-confirm="Are you sure?" class="btn btn-sm btn-danger">Delete</a>
                <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}/move_up" data-method="patch" class="btn btn-sm btn-secondary">Up</a>
                <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}/move_down" data-method="patch" class="btn btn-sm btn-secondary">Down</a>
              </div>
            </div>
          `
          this.listTarget.appendChild(li)
          window.location.reload()
        } else {

          console.error('Expected JSON response')
        }
      } else {
        console.error('Failed to add page')
      }
    }
  }

  async addService(event) {
    if (event.target.checked) {
      const serviceId = event.target.value
      const serviceTitle = event.target.dataset.title
      const serviceSlug = event.target.dataset.url

      const response = await fetch(`/admin/menus/${this.data.get("menuIdValue")}/menu_items`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        },
        body: JSON.stringify({ menu_item: { title: serviceTitle, url: serviceSlug, item_type: 'service', item_id: serviceId } })
      })

      if (response.ok) {
        const data = await response.json()
        const li = document.createElement("li")
        li.dataset.id = data.id
        li.innerHTML = `
          <div class="flex justify-between items-center">
            <span>${serviceTitle}</span>
            <div>
              <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}/edit" class="btn btn-sm btn-secondary">Edit</a>
              <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}" data-method="delete" data-confirm="Are you sure?" class="btn btn-sm btn-danger">Delete</a>
              <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}/move_up" data-method="patch" class="btn btn-sm btn-secondary">Up</a>
              <a href="/admin/menus/${this.data.get("menuIdValue")}/menu_items/${data.id}/move_down" data-method="patch" class="btn btn-sm btn-secondary">Down</a>
            </div>
          </div>
        `
        this.listTarget.appendChild(li)
        window.location.reload()
      } else {
        console.error('Failed to add service')
      }
    }
  }

  addCategory(event) {
    const categoryId = event.target.value
    const categoryTitle = event.target.dataset.title
    const categorySlug = event.target.dataset.slug

    if (event.target.checked) {
      this.addMenuItem(categoryTitle, categorySlug, "category", categoryId)
    } else {
      this.removeMenuItem(categorySlug, "category")
    }
  }

  async updateParent(event) {
    const menuItemId = event.target.dataset.menuItemId
    const parentId = event.target.value
    const url = `/admin/menus/${this.data.get("menuIdValue")}/menu_items/${menuItemId}/update_parent`
    
    const response = await fetch(url, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      },
      body: JSON.stringify({ menu_item: { parent_id: parentId } })
    })

    if (response.ok) {
      location.reload()  // Reload the page to reflect the changes
    } else {
      console.error('Failed to update parent')
    }
  }

  addSubmenu(event) {
    const parentId = event.target.dataset.parentId
    const submenuTitle = prompt("Enter submenu title:")
    if (submenuTitle) {
      const newItem = document.createElement("li")
      newItem.innerHTML = `
        <span>${submenuTitle}</span>
        <input type="hidden" name="menu[menu_items_attributes][][title]" value="${submenuTitle}">
        <input type="hidden" name="menu[menu_items_attributes][][parent_id]" value="${parentId}">
        <input type="hidden" name="menu[menu_items_attributes][][item_type]" value="custom">
      `
      const parentItem = this.listTarget.querySelector(`[data-id="${parentId}"]`)
      let submenuList = parentItem.querySelector("ul")
      if (!submenuList) {
        submenuList = document.createElement("ul")
        parentItem.appendChild(submenuList)
      }
      submenuList.appendChild(newItem)
    }
  }

  addMenuItem(title, slug, type, id) {
    const list = this.listTarget
    const newItem = document.createElement("li")
    newItem.dataset.id = id
    newItem.innerHTML = `
      <span>${title}</span>
      <input type="hidden" name="menu[menu_items_attributes][][title]" value="${title}">
      <input type="hidden" name="menu[menu_items_attributes][][slug]" value="${slug}">
      <input type="hidden" name="menu[menu_items_attributes][][item_type]" value="${type}">
      <input type="hidden" name="menu[menu_items_attributes][][item_id]" value="${id}">
      <button type="button" data-action="click->menu-items#addSubmenu" data-parent-id="${id}">Add Submenu</button>
    `
    list.appendChild(newItem)
    window.location.reload()
  }

  removeMenuItem(slug, type) {
    const list = this.listTarget
    const items = list.querySelectorAll(`li`)
    items.forEach(item => {
      if (item.querySelector(`input[name="menu[menu_items_attributes][][slug]"]`).value === slug && 
          item.querySelector(`input[name="menu[menu_items_attributes][][item_type]"]`).value === type) {
        item.remove()
      }
    })
  }
}
