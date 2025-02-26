module Admin
  class MenuItemsController < ApplicationController
    before_action :set_menu
    before_action :set_menu_item, only: [:edit, :update, :destroy]

    def new
      @menu = Menu.find(params[:menu_id])
     # @menu_item = @menu.menu_items.new(parent_id: params[:parent_id])
     @menu_item = @menu.menu_items.build

    end

    def create
      @menu_item = @menu.menu_items.build(menu_item_params)
      if @menu_item.save
  
        respond_to do |format|
          format.json { render json: @menu_item, status: :created }
          format.html { redirect_to edit_admin_menu_path(@menu), notice: 'Menu item was successfully created.' }

        end
      else
        respond_to do |format|
          format.html { redirect_to edit_admin_menu_path(@menu), alert: 'Failed to create menu item.' }
          format.json { render json: @menu_item.errors, status: :unprocessable_entity }
        end
      end
    end

    def edit
      
      load_items_for_select

    end

    def update_parent
      
      @menu_item = MenuItem.find(params[:menu_item_id])
      if @menu_item.update(parent_id: params[:menu_item][:parent_id])
        render json: { success: true }
      else
        render json: { success: false }
      end
    end

    def update
      if @menu_item.update(menu_item_params)
        redirect_to edit_admin_menu_path(@menu_item.menu), notice: 'Menu item was successfully updated.'
      else
        render :edit
      end
    end

    def destroy
      @menu_item.destroy
      redirect_to edit_admin_menu_path(@menu_item.menu), notice: 'Menu item was successfully deleted.'
    end

    def update_position
      @menu_item = MenuItem.find(params[:id])
      @menu_item.insert_at(params[:position].to_i)
      head :ok
    end

    private

    def load_items_for_select
      @menu_items_options = @menu.menu_items.where.not(id: @menu_item.id).pluck(:title, :id)
    end

    def set_menu_item
      @menu_item = MenuItem.find(params[:id])
    end

    def set_menu
      @menu = Menu.find(params[:menu_id])
    end

    def menu_item_params
      params.require(:menu_item).permit(:title, :url, :parent_id, :position, :menu_id, :type, :type_id, :item_type, :item_id)
    end
  end
end
