module Admin
    class TerminalsController < ApplicationController
      before_action :set_terminal, only: [:update_category]
      def index
        @terminals = Terminal.all
      end
  
      def new
        @terminal = Terminal.new
      end
  
      def create
        @terminal = Terminal.new(terminal_params)


        if @terminal.save
          redirect_to admin_terminals_path, notice: 'Terminal was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @terminal = Terminal.find_by_slug(params[:id])
      end
  
      def update
        @terminal = Terminal.find_by_slug(params[:id])
      
        # Update the terminal attributes first
        if @terminal.update(terminal_params)
          # If the terminal has content, process the ActionText content to replace <h1> with <h2>
          if @terminal.content.present?
            @terminal.content.body = convert_h1_to_h2(@terminal.content.body.to_s)
            @terminal.content.save # Ensure the changes to the RichText object are persisted
          end
      
          redirect_to edit_admin_terminal_path(@terminal), notice: 'Terminal was successfully updated.'
        else
          render :edit, alert: 'Failed to update the terminal.'
        end
      end
          

      def update_category

        if @terminal.update(terminal_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end

      def delete_all
        Terminal.destroy_all
        redirect_to admin_terminals_path, notice: 'All terminals have been deleted successfully.'
      end
  
      def destroy
        @terminal = Terminal.find(params[:id])
        @terminal.destroy
        redirect_to admin_terminals_path, notice: 'Terminal was successfully deleted.'
      end
  
      private
  
      def set_terminal
        
        @terminal = Terminal.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def terminal_params
        params.require(:terminal).permit(:title, :content, :category_id, :meta_description, :meta_keywords, :template, images: [], remove_images: []).merge(user_id: current_user.id)

      end
    end
  end
  