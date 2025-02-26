class CommunityController < ApplicationController
    before_action :authenticate_user!, only: [:create_medium]

    # Action to handle screenshot uploads
    def create_medium
        @medium = Medium.new(medium_params)
        @medium.user = current_user
        @medium.category = 'screenshot'
        @medium.approved = false # All uploads require admin approval by default
      
        if params[:file].present?
          uploaded_file = params[:file]
          @medium.file.attach(
            io: uploaded_file.tempfile,
            filename: uploaded_file.original_filename,
            content_type: uploaded_file.content_type
          )
        end
      
        if @medium.save
          redirect_to screenshots_community_index_path, notice: 'Your screenshot has been submitted and is awaiting approval.'
        else
          flash[:alert] = 'Failed to upload screenshot.'
          render :screenshots
        end
      end
      

    def screenshots
        @page = Page.find_by_slug('screenshots')
        @approved_screenshots = Medium.screenshots.where(approved: true).order(created_at: :desc)
        @staff_screenshots = Medium.screenshots.joins(:user).where(users: { user_type: 'admin' }, approved: true) # Staff screenshots
        @usernames = User.joins(:media).where(media: { category: 'screenshot', approved: true }).distinct.pluck(:username) # Usernames of submitters
        render "pages/screenshots"
    end

    def user_screenshots
        username = params[:username]
        user = User.find_by(username: username)
      
        if user
          screenshots = user.media.screenshots.where(approved: true).order(created_at: :desc)
          render json: {
            primary_image: screenshots.first&.file&.url,
            meta_description: screenshots.first&.meta_description,
            meta_keywords: screenshots.first&.meta_keywords,
            thumbnails: screenshots.map do |s|
              { url: s.file.url, meta_description: s.meta_description }
            end
          }
        else
          render json: { error: 'User not found' }, status: :not_found
        end
      end
      


    private

    def medium_params
      params.permit(:file, :meta_description, :meta_keywords)
    end

end