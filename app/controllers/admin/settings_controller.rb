module Admin
    class SettingsController < Admin::ApplicationController
      before_action :set_setting, only: [:edit, :update, :destroy]
  
      def index
        @settings = Setting.all
      end
  
      def new
        @setting = Setting.new
      end
  
      def create
        @setting = Setting.new(setting_params)
        if @setting.save
          redirect_to admin_settings_path, notice: 'Setting was successfully created.'
        else
          render :new
        end
      end
  
      def edit
      end
  
      def update
        if @setting.update(setting_params)
          redirect_to admin_settings_path, notice: 'Setting was successfully updated.'
        else
          render :edit
        end
      end
  
      def destroy
        @setting.destroy
        redirect_to admin_settings_path, notice: 'Setting was successfully deleted.'
      end

      private
  
      def set_setting
        @setting = Setting.find(params[:id])
      end
  
      def setting_params
        params.require(:setting).permit(:key, :value, :group, :setting_type, :image)
      end
    end
  end
  