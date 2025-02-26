module Admin
    class SectionsController < Admin::ApplicationController
    before_action :set_section, only: [:show, :edit, :update, :destroy, :move_up, :move_down]
  
    def index
      @sections = Section.all
    end
  
    def show
    end
  
    def new
      @section = Section.new
    end
  
    def create
      @section = Section.new(section_params)
      if @section.save
        redirect_to admin_section_path(@section), notice: 'Section was successfully created.'
      else
        render :new
      end
    end
  
    def edit
    end
  
    def update
      if @section.update(section_params)
        redirect_to admin_section_path(@section), notice: 'Section was successfully updated.'
      else
        render :edit
      end
    end
  
    def destroy
      @section.destroy
      redirect_to admin_sections_path, notice: 'Section was successfully deleted.'
    end
  
    def move_up
      @section.decrement!(:position)
      redirect_to admin_sections_path
    end
  
    def move_down
      @section.increment!(:position)
      redirect_to admin_sections_path
    end
  
    private
  
    def set_section
      @section = Section.find(params[:id])
    end
  
    def section_params
      params.require(:section).permit(:name, :template, :animation_speed, :position)
    end
  end
end