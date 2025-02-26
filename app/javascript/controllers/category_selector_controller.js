import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    
    static targets = ["select"]

    connect() {
      this.selectTarget.addEventListener("change", this.updateCategory.bind(this))
      
    }
  
    updateCategory(event) {
        const categoryId = event.target.value
        const modelId = this.element.dataset.modelId
        const modelName = this.element.dataset.modelName
    
        if (categoryId && modelId && modelName) {
          // Pluralize the model name to match Rails routes
          const pluralModelName = modelName.endsWith('s') ? modelName : `${modelName}s`
          
          fetch(`/admin/${pluralModelName}/${modelId}/update_category`, {
            method: "PATCH",
            headers: {
              "Content-Type": "application/json",
              "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content
            },
            body: JSON.stringify({ [modelName]: { category_id: categoryId } })
          })
          .then(response => response.json())
          .then(data => {
            if (data.success) {
              console.log("Category updated successfully")
            } else {
              console.error("Error updating category")
            }
          })
        }
      }

}
