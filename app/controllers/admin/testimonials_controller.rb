module Admin
    class TestimonialsController < ApplicationController
      def index
        @testimonials = Testimonial.all
      end
  
      def new
        @testimonial = Testimonial.new
      end
  
      def create
        @testimonial = Testimonial.new(testimonial_params)
        if @testimonial.save
          redirect_to admin_testimonials_path, notice: 'Testimonial was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @testimonial = Testimonial.find(params[:id])
      end
  
      def update
        @testimonial = Testimonial.find(params[:id])
        if @testimonial.update(testimonial_params)
          redirect_to admin_testimonials_path, notice: 'Testimonial was successfully updated.'
        else
          render :edit
        end
      end
  
      def destroy
        @testimonial = Testimonial.find(params[:id])
        @testimonial.destroy
        redirect_to admin_testimonials_path, notice: 'Testimonial was successfully deleted.'
      end
  
      private
  
      def testimonial_params
        params.require(:testimonial).permit(:title, :content, :category_id)
      end
    end
  end
  