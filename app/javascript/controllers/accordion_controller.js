import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["content"];

    toggle(event) {
      const button = event.currentTarget;
      const content = this.contentTargets.find(content => content.dataset.accordionId === button.dataset.accordionId);
  
      if (content.classList.contains("hidden")) {
        this.contentTargets.forEach((content) => content.classList.add("hidden"));
        content.classList.remove("hidden");
      } else {
        content.classList.add("hidden");
      }
    }
}
