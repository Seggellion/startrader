import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="google-map"
export default class extends Controller {
  static targets = ["map"]

  connect() {
    this.initMap()
  }

  initMap() {
    // Get address from data attributes
    const address = {
      line1: this.data.get('line1'),
      line2: this.data.get('line2'),
      city: this.data.get('city'),
      state: this.data.get('state'),
      zip: this.data.get('zip')
    }

    const storeName = this.data.get('storeName')

    // Format address string
    const addressString = `${address.line1}, ${address.line2}, ${address.city}, ${address.state} ${address.zip}`

    // Initialize map
    const map = new google.maps.Map(this.mapTarget, {
      zoom: 15,
      center: { lat: -34.397, lng: 150.644 }
    })

    // Geocode address
    const geocoder = new google.maps.Geocoder()
    geocoder.geocode({ 'address': addressString }, function(results, status) {
      if (status == 'OK') {
        map.setCenter(results[0].geometry.location)
        
        const contentString = `
          <div class="info-window-content">
            <strong>${storeName}</strong>
          </div>
        `
        const infowindow = new google.maps.InfoWindow({
          content: contentString
        })

        const marker = new google.maps.Marker({
          map: map,
          position: results[0].geometry.location
        })

        marker.addListener('click', function() {
          infowindow.open(map, marker)
        })

        // Automatically open the info window when the map loads
        infowindow.open(map, marker)
      } else {
        console.error('Geocode was not successful for the following reason: ' + status)
      }
    })
  }
}
