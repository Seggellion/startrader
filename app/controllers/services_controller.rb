class ServicesController < ApplicationController
    def show
      @service = Service.friendly.find(params[:id])
    end
    def index
      @service = Service.all
    end
  end
  