module Admin
  class MenusController < ApplicationController
    before_action :set_menu, only: [:edit, :update, :destroy]

    def index
      @menus = Menu.all
    end

    def new
      @menu = Menu.new
    end

    def create
      
      @menu = Menu.new(menu_params)
      if @menu.save
        redirect_to edit_admin_menu_path(@menu), notice: 'Menu was successfully created.'
      else
        render :new
      end
    end

    def edit
      @services = Service.all
      @pages = Page.all
      @categories = Category.all
      load_menu_items_for_select
    end

    def update

      if @menu.update(menu_params)
        redirect_to edit_admin_menu_path(@menu), notice: 'Menu was successfully updated.'
      else
        render :edit
      end
    end

    def destroy
      @menu.destroy
      redirect_to admin_menus_path, notice: 'Menu was successfully deleted.'
    end

    private

    
    def load_menu_items_for_select
      @menu_items_options = @menu.menu_items.pluck(:title, :id)
    end

    def set_menu
      @menu = Menu.find(params[:id])
    end

    def menu_params
      params.require(:menu).permit(:name)
    end
  end
end
