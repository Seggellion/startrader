import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["slides"]

  connect() {
    this.currentIndex = 0
    this.animationSpeed = this.element.dataset.animationSpeed || 1000
    this.showSlide(this.currentIndex)
    this.startAutoSlide()
  }

  startAutoSlide() {
    this.interval = setInterval(() => {
      this.next()
    }, 5000)
  }

  next() {
    this.moveSlide("next")
  }

  prev() {
    this.moveSlide("prev")
  }

  moveSlide(direction) {
    const slides = this.slidesTarget.children
    const previousIndex = this.currentIndex
    
    if (direction === "next") {
      this.currentIndex = (this.currentIndex + 1) % slides.length
    } else {
      this.currentIndex = (this.currentIndex - 1 + slides.length) % slides.length
    }
    
    this.showSlide(this.currentIndex, previousIndex)
  }

  showSlide(currentIndex, previousIndex) {
    const slides = this.slidesTarget.children
    Array.from(slides).forEach((slide, i) => {
      if (i === currentIndex) {
        slide.style.transition = `transform ${this.animationSpeed}ms ease`
        slide.style.transform = `translateX(0%)`
      } else if (i === previousIndex) {
        slide.style.transition = `transform ${this.animationSpeed}ms ease`
        slide.style.transform = `translateX(${currentIndex > previousIndex ? '-100%' : '100%'})`
      } else {
        slide.style.transition = 'none'
        slide.style.transform = `translateX(${(i - currentIndex) * 100}%)`
      }
    })
  }

  disconnect() {
    clearInterval(this.interval)
  }
}

