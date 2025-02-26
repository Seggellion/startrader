import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["atlasPages"];
  static values = {
    currentSlug: String,
    atlasPages: Array,
  };

connect(){
  console.log('playguide');
}

  navigateToPage(event) {
    const selectedSlug = event.target.value;
    if (selectedSlug) {
      window.location.href = `/playguide/atlas/${selectedSlug}`;
    }
  }

  navigateForward() {
    const currentIndex = this.currentIndex();
    const nextIndex = (currentIndex + 1) % this.atlasPagesValue.length;
    this.navigateToSlug(this.atlasPagesValue[nextIndex].slug);
  }

  navigateBackward() {
    const currentIndex = this.currentIndex();
    const prevIndex =
      (currentIndex - 1 + this.atlasPagesValue.length) %
      this.atlasPagesValue.length;
    this.navigateToSlug(this.atlasPagesValue[prevIndex].slug);
  }

  currentIndex() {
    return this.atlasPagesValue.findIndex(
      (page) => page.slug === this.currentSlugValue
    );
  }

  navigateToSlug(slug) {
    if (slug) {
      window.location.href = `/playguide/atlas/${slug}`;
    }
  }
}
