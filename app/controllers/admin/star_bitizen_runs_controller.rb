module Admin
    class StarBitizenRunsController < ApplicationController
      def index
        @star_bitizen_runs = StarBitizenRun.order(updated_at: :desc)
      end
  
      def new
        @star_bitizen_run = StarBitizenRun.new
      end
  
      def create
        @star_bitizen_run = StarBitizenRun.new(star_bitizen_run_params)


        if @star_bitizen_run.save
          redirect_to admin_star_bitizen_runs_path, notice: 'StarBitizenRun was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @star_bitizen_run = StarBitizenRun.find_by_id(params[:id])
      end
  
      def update
        @star_bitizen_run = StarBitizenRun.find_by_id(params[:id])
      
        # Update the star_bitizen_run attributes first
        if @star_bitizen_run.update(star_bitizen_run_params)
          # If the star_bitizen_run has content, process the ActionText content to replace <h1> with <h2>

          redirect_to edit_admin_star_bitizen_run_path(@star_bitizen_run), notice: 'StarBitizenRun was successfully updated.'
        else
          render :edit, alert: 'Failed to update the star_bitizen_run.'
        end
      end
          


      
      def delete_all
        StarBitizenRun.where(classification:"star_bitizen_run").destroy_all
        redirect_to admin_star_bitizen_runs_path, notice: 'All star_bitizen_runs have been deleted successfully.'
      end
  
      def destroy
        @star_bitizen_run = StarBitizenRun.find(params[:id])
        @star_bitizen_run.destroy
        redirect_to admin_star_bitizen_runs_path, notice: 'StarBitizenRun was successfully deleted.'
      end
  
      private
  
      def set_star_bitizen_run
        
        @star_bitizen_run = StarBitizenRun.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def star_bitizen_run_params
        params.require(:star_bitizen_run).permit(
          :name
        )
      end
      
    end
  end
  