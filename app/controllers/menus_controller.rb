class MenusController < ApplicationController
    def footer
      @footer_menu_items = Menu.for_location('footer')
    end
  end
  