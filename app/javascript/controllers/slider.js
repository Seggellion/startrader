import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"];

  initialize() {
    this.currentIndex = 0;
    this.totalSlides = this.containerTarget.children.length;
    this.startAutoSlide();
  }

  next() {
    this.currentIndex = (this.currentIndex + 1) % this.totalSlides;
    this.updateSlidePosition();
  }

  previous() {
    this.currentIndex =
      (this.currentIndex - 1 + this.totalSlides) % this.totalSlides;
    this.updateSlidePosition();
  }

  updateSlidePosition() {
    const offset = -this.currentIndex * 100;
    this.containerTarget.style.transform = `translateX(${offset}%)`;
  }

  startAutoSlide() {
    this.interval = setInterval(() => {
      this.next();
    }, 10000); // Change slide every 10 seconds
  }

  stopAutoSlide() {
    clearInterval(this.interval);
  }

  connect() {
    this.element.addEventListener("mouseenter", () => this.stopAutoSlide());
    this.element.addEventListener("mouseleave", () => this.startAutoSlide());
  }

  disconnect() {
    this.stopAutoSlide();
  }
}
