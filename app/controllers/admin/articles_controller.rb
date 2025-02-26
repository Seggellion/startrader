module Admin
    class ArticlesController < ApplicationController
      def index
        @articles = Article.all
      end
  
      def new
        @article = Article.new
      end
  
      def create
        @article = Article.new(article_params)
        if @article.save
          redirect_to admin_articles_path, notice: 'Article was successfully created.'
        else
          render :new
        end
      end
  
      def edit
      
        @article = Article.find_by_slug(params[:id])
      end
  
      def update
        @article = Article.find_by_slug(params[:id])
        if @article.update(article_params)
          redirect_to admin_articles_path, notice: 'Article was successfully updated.'
        else
          render :edit
        end
      end

      def update_category
        @article = Article.find_by_id(params[:id])
        if @article.update(article_params)
          render json: { success: true }
        else
          render json: { success: false }
        end
      end
  
      def destroy
        @article = Article.find_by_slug(params[:id])

        @article.destroy
        redirect_to admin_articles_path, notice: 'Article was successfully deleted.'
      end
  
      private
  
      def article_params
        params.require(:article).permit(:title, :content, :meta_description, :meta_keywords, :category_id).merge(user_id: current_user.id)
      end
      
    end
  end
  