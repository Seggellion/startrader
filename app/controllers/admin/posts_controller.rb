module Admin
    class PostsController < ApplicationController
      before_action :set_post, only: [:update_category]
      def index
        @posts = Post.all
      end
  
      def new
        @post = Post.new
      end
  
      def create
        @post = Post.new(post_params)
        if @post.save
          redirect_to admin_posts_path, notice: 'Post was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @post = Post.find_by_slug(params[:id])
      end
  
      def update
        @post = Post.find_by_slug(params[:id])
        if @post.update(post_params)
           redirect_to edit_admin_post_path(@post), notice: 'Post was successfully updated.'
        end
      end

      def update_category

        if @post.update(post_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end

  
      def destroy
        @post = Post.find(params[:id])
        @post.destroy
        redirect_to admin_posts_path, notice: 'Post was successfully deleted.'
      end
  
      private
  
      def set_post
        
        @post = Post.find(params[:id])
      end

      def post_params
        params.require(:post).permit(:title, :content, :category_id, :meta_description, :meta_keywords, :template, images: [], remove_images: []).merge(user_id: current_user.id)

      end
    end
  end
  