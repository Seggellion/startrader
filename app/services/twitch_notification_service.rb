# app/services/twitch_notification_service.rb
class TwitchNotificationService
  API_URL = "https://starbitizen.altama.energy/"

  def self.notify_arrival(username, location_name)
    return unless username && location_name

    uri = URI.join(API_URL, "notify_arrival")
    params = { username: username, location: location_name }
    
    begin
      response = Net::HTTP.post(uri, params.to_json, { "Content-Type" => "application/json" })
      
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("TwitchNotificationService failed: #{response.code} - #{response.body}")
      end
    rescue => e
      Rails.logger.error("TwitchNotificationService error: #{e.message}")
    end
  end
end
