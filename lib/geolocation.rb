# lib/geolocation.rb

require 'net/http'
require 'json'
require 'uri'

module Geolocation
  def self.get_location_from_ip(ip_address)
    api_key = Setting.get('google_api_key')
    geolocation_url = URI("https://www.googleapis.com/geolocation/v1/geolocate?key=#{api_key}")

    request_payload = {
      'considerIp' => true
    }

    http = Net::HTTP.new(geolocation_url.host, geolocation_url.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(geolocation_url)
    request['Content-Type'] = 'application/json'
    request.body = request_payload.to_json

    response = http.request(request)
    location_data = JSON.parse(response.body)

    if location_data['location']
      latitude = location_data['location']['lat']
      longitude = location_data['location']['lng']
      country_code = get_country_code_from_coordinates(latitude, longitude, api_key)
      { latitude: latitude, longitude: longitude, country_code: country_code }
    else
      { error: location_data['error']['message'] }
    end
  end

  def self.get_country_code_from_coordinates(latitude, longitude, api_key)
    geocode_url = URI("https://maps.googleapis.com/maps/api/geocode/json?latlng=#{latitude},#{longitude}&key=#{api_key}")
    
    http = Net::HTTP.new(geocode_url.host, geocode_url.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(geocode_url)
    
    response = http.request(request)
    location_data = JSON.parse(response.body)
    
    if location_data['results'].any?
      country = location_data['results'].find do |result|
        result['types'].include?('country')
      end
      country['address_components'][0]['short_name'] if country
    else
      nil
    end
  end
end
