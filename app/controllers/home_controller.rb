class HomeController < ApplicationController

    def index
        @articles = Article.all
        @services = Service.all
        @homepage_services = Service.joins(:category).where(categories: { name: 'home-page' })
        @contact_message = ContactMessage.new
        @testimonials = Testimonial.by_category_name('home-page')
        @sections = Section.all
        @events = Event.all
        @facilities_by_location = ProductionFacility
        .includes(:commodity)
        .group_by(&:location_name)
    end

    def news
        @articles =  Article.joins(:category).where(categories: {slug: "news"}).order(created_at: :desc)
    render "pages/news"
    end

end