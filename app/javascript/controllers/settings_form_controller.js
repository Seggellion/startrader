import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="settings-form"
export default class extends Controller {
  static targets = ["settingType", "valueField", "colorField", "uploadField"]

  connect() {
    this.toggleFields()
  }


  toggleFields() {
    const settingType = this.settingTypeTarget.value

    if (settingType === 'color') {
      this.valueFieldTarget.style.display = 'none'
      this.valueFieldTarget.removeAttribute('name')
      this.colorFieldTarget.style.display = 'block'
      this.colorFieldTarget.querySelector('input').setAttribute('name', 'setting[value]')
      this.uploadFieldTarget.style.display = 'none'
      this.uploadFieldTarget.querySelector('input').removeAttribute('name')
    } else if (settingType === 'image') {
      this.valueFieldTarget.style.display = 'none'
      this.valueFieldTarget.removeAttribute('name')
      this.uploadFieldTarget.style.display = 'block'
      this.uploadFieldTarget.querySelector('input').setAttribute('name', 'setting[image]')
      this.colorFieldTarget.style.display = 'none'
      this.colorFieldTarget.querySelector('input').removeAttribute('name')
    } else {
      this.valueFieldTarget.style.display = 'block'
      this.valueFieldTarget.querySelector('textarea, input').setAttribute('name', 'setting[value]')
      this.colorFieldTarget.style.display = 'none'
      this.colorFieldTarget.querySelector('input').removeAttribute('name')
      this.uploadFieldTarget.style.display = 'none'
      this.uploadFieldTarget.querySelector('input').removeAttribute('name')
    }
  }
}
