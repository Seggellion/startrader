module Admin
    class BlocksController < Admin::ApplicationController
      before_action :set_block, only: [:edit, :update, :destroy, :move_up, :move_down]
      before_action :set_section, only: [:new, :create]
  
      def new
        @block = @section.blocks.build
      end
  
      def create
        
        @block = @section.blocks.build(block_params)
        if @block.save
          if @block.image?
            @block.image.attach(block_params[:image])
          end
          redirect_to admin_section_path(@section), notice: 'Block was successfully created.'
        else
          render :new
        end
      end
  
      def edit
      end
  
      def update
   
        if @block.update(block_params)
          if @block.image? && block_params[:content].present?
            @block.image.attach(block_params[:content])
          end
          redirect_to admin_section_path(@block.section), notice: 'Block was successfully updated.'
        else
          render :edit
        end
      end
  
      def destroy
        @block.destroy
        redirect_to admin_section_path(@block.section), notice: 'Block was successfully deleted.'
      end
  
      def move_up
        @block.decrement!(:position)
        redirect_to admin_section_path(@block.section)
      end
  
      def move_down
        @block.increment!(:position)
        redirect_to admin_section_path(@block.section)
      end
  
      private
  
      def set_block
        @block = Block.find(params[:id])
      end
  
      def set_section
        @section = Section.find(params[:section_id])
      end
  
      def block_params
        params.require(:block).permit(:block_type, :content, :position, :image)
      end
    end
  end
  