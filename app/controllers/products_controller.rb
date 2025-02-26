# app/controllers/products_controller.rb

class ProductsController < ApplicationController
    before_action :initialize_shopify_service
  
    def index
      @products = @shopify_service.fetch_products
    end
  
    def show
      product_handle = params[:handle]
      @product = @shopify_service.fetch_product_by_handle(product_handle)
    end
  
    def add_to_cart
      variant_id = params[:variant_id]
      cart_id = session[:cart_id] || @shopify_service.create_cart["id"]
      session[:cart_id] = cart_id
      @shopify_service.add_to_cart(cart_id, variant_id)
      redirect_to cart_path
    end
  
    def cart
      @cart = @shopify_service.fetch_cart(session[:cart_id])
    end
  
    def remove_from_cart
        variant_id = params[:line_id]
        cart_id = session[:cart_id]

        @shopify_service.remove_from_cart(cart_id, variant_id)
        redirect_to cart_path, notice: 'Item removed from cart.'
    end

    def checkout
      @cart = @shopify_service.fetch_cart(session[:cart_id])
      
      redirect_to @cart["checkoutUrl"], allow_other_host: true
    end
  
    private
  
    def initialize_shopify_service
      @shopify_service = ShopifyService.new
    end
  end
  