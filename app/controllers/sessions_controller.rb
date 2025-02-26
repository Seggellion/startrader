class SessionsController < ApplicationController
  layout 'utility'

  def destroy
    session[:user_id] = nil
    redirect_to root_path, notice: 'Logged out!'
  end

  def failure
    redirect_to root_path, alert: 'Authentication failed.'
  end

  def create
    auth = request.env['omniauth.auth']
    provider = auth['provider']

    # Step 1: Authenticate User
    user = User.find_or_create_by(uid: auth['uid'], provider: provider) do |u|
      u.email = auth['info']['email']
      u.first_name = auth['info']['name']
      u.twitch_id = auth['uid']
      u.username = auth['info']['name']
      u.user_type = User.admin_exists? ? 1 : 0
    end

  avatar_url = auth['info']['image']

    # If you're using ActiveStorage to attach the avatar
    user.avatar.attach(io: URI.open(avatar_url), filename: "#{user.username}_avatar.jpg") if avatar_url.present?
  
    session[:user_id] = user.id

     # Redirect based on user role
    if user.admin?
      redirect_to admin_root_path, notice: 'Welcome, Admin!'
    else
      redirect_to root_path, notice: 'Welcome back!'
    end

  end

  private

  def fetch_minecraft_uuid(access_token)
    # Fetch Xbox Live Token
    xbl_token = get_xbl_token(access_token)

    return nil unless xbl_token

    # Fetch XSTS Token
    
    xsts_token = get_xsts_token(xbl_token)
    return nil unless xsts_token

    # Fetch Minecraft Profile
    get_minecraft_profile(xsts_token)
  end

  def get_xbl_token(access_token)
    url = 'https://user.auth.xboxlive.com/user/authenticate'
    # Rename 'response' to 'api_response'
    api_response = HTTParty.post(url, {
      headers: { 'Content-Type' => 'application/json' },
      body: {
        Properties: {
          AuthMethod: 'RPS',
          SiteName: 'user.auth.xboxlive.com',
          RpsTicket: "d=#{access_token}"
        },
        RelyingParty: 'http://auth.xboxlive.com',
        TokenType: 'JWT'
      }.to_json
    })

    # Optional: check status or log
    return nil unless api_response.code == 200

    # Now safely call parsed_response on the HTTParty response
    api_response.parsed_response.dig('Token')
  end

  def get_xsts_token(xbl_token)
    url = 'https://xsts.auth.xboxlive.com/xsts/authorize'

    api_response = HTTParty.post(url, {
      headers: { 'Content-Type' => 'application/json' },
      body: {
        Properties: {
          SandboxId: 'RETAIL',
          UserTokens: [xbl_token]
        },
        RelyingParty: 'rp://api.minecraftservices.com/',
        TokenType: 'JWT'
      }.to_json
    })

    return nil unless api_response.code == 200
    api_response.parsed_response.dig('Token')
  end

  def get_minecraft_profile(xsts_token)
    url = 'https://api.minecraftservices.com/minecraft/profile'

    api_response = HTTParty.get(url, {
      headers: { 'Authorization' => "Bearer #{xsts_token}" }
    })

    return nil unless api_response.code == 200

    profile = api_response.parsed_response
    profile['id'] # This is the Minecraft UUID
  end
end
