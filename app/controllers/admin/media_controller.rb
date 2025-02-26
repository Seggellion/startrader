module Admin
  class MediaController < Admin::ApplicationController
    before_action :set_medium, only: [:approve, :destroy]

    def index
      @media_files = Medium.where.not(category: 'screenshot').where(approved: true) # Approved non-screenshot media
      @pending_files = Medium.where.not(category: 'screenshot').where(approved: false) # Pending non-screenshot media
    end

    def screenshots
      @approved_screenshots = Medium.where(category: 'screenshot', approved: true) # Approved screenshots
      @pending_screenshots = Medium.where(category: 'screenshot', approved: false) # Pending screenshots
    end

    def create
      @media = Medium.new(media_params)
      @media.user = current_user # Assign the current user
      @media.approved = true if admin_signed_in? # Automatically approve if admin
      if @media.save
        redirect_to admin_medium_path, notice: 'Media uploaded successfully.'
      else
        render :new
      end
    end

    def approve
      @media.update(approved: true)
      redirect_back fallback_location: admin_medium_path, notice: 'Media approved successfully.'
    end

    def destroy
  
      @media.file.purge
      @media.destroy
      redirect_back fallback_location: admin_medium_path, notice: 'Media deleted successfully.'
    end

    private

    def set_medium
      @media = Medium.find(params[:id])
    end

    def media_params
      params.require(:medium).permit(:file, :meta_description, :meta_keywords, :category)
    end
  end
end
