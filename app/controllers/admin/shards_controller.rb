module Admin
    class ShardsController < ApplicationController
      def index
        @shards = Shard.all
      end
  
      def new
        @shard = Shard.new
      end
  
      def create
        @shard = Shard.new(shard_params)


        if @shard.save
          redirect_to admin_shards_path, notice: 'Commodity was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @shard = Shard.find_by_id(params[:id])
      end
  
      def update
        @shard = Shard.find_by_id(params[:id])
      
        # Update the shard attributes first
        if @shard.update(shard_params)
          # If the shard has content, process the ActionText content to replace <h1> with <h2>

          redirect_to edit_admin_shard_path(@shard), notice: 'Commodity was successfully updated.'
        else
          render :edit, alert: 'Failed to update the shard.'
        end
      end
          


      
      def delete_all
        Shard.where(classification:"shard").destroy_all
        redirect_to admin_shards_path, notice: 'All shards have been deleted successfully.'
      end
  
      def destroy
        @shard = Shard.find(params[:id])
        @shard.destroy
        redirect_to admin_shards_path, notice: 'Shard was successfully deleted.'
      end
  
      private
  
      def set_shard
        
        @shard = Commodity.find(params[:id])
      end


      def shard_params
        params.require(:shard).permit(
          :name,
          :region,
          :channel_uuid        
        )
      end
      
    end
  end
  