Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "https://starbitizen.com",
            "https://www.starbitizen.com",
            "https://maidenbot.com"

    resource "/api/ships",
      headers: :any,
      methods: [:get, :head, :options],
      credentials: false,
      max_age: 600

    resource "/api/locations",
      headers: :any,
      methods: [:get, :head, :options],
      credentials: false,
      max_age: 600

    resource "/api/commodities",
      headers: :any,
      methods: [:get, :head, :options],
      credentials: false,
      max_age: 600
  end
end
