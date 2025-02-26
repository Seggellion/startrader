import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["contentField", "dynamicField", "contentValue"]

  connect() {
    this.toggleFields()
  }

  toggleFields() {
    const blockType = event ? event.target.value : this.element.querySelector("select").value
    let contentInput

    switch (blockType) {
      case "image":
        contentInput = `<input type="file" name="block[image]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" data-block-form-target="contentValue">`
        break
      case "rich_text":
        contentInput = `<textarea name="block[content]" class="trix-content mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" data-block-form-target="contentValue">${this.contentValueTarget.value}</textarea>`
        break
      case "single_line_text":
        contentInput = `<input type="text" name="block[content]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" value="${this.contentValueTarget.value}" data-block-form-target="contentValue">`
        break
      case "json":
        contentInput = `<textarea name="block[content]" rows="5" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" data-block-form-target="contentValue">${this.contentValueTarget.value}</textarea>`
        break
      default:
        contentInput = `<textarea name="block[content]" rows="5" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" data-block-form-target="contentValue">${this.contentValueTarget.value}</textarea>`
        break
    }

    this.dynamicFieldTarget.innerHTML = contentInput
  }  
}
