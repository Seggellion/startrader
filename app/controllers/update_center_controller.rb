
class UpdateCenterController < ApplicationController
    def index
  render "pages/update-center"
    end

    def fyi
        @articles =  Article.joins(:category).where(categories: {slug: "update-center"}).order(created_at: :desc)
    render "pages/fyi"
    end
  end
  