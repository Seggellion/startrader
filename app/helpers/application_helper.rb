module ApplicationHelper
  def meta_title
    if content_for?(:meta_title)
      content_for(:meta_title)
    elsif @service.is_a?(ActiveRecord::Relation)
      "List of Services" # Adjust this as needed for other models
    elsif @service&.title.present?
      @service.title
    elsif @page&.title.present?
      @page.title
    elsif @article&.title.present?
      @article.title
    else
      Setting.get('site-title') || "Default Title"
    end
  end
  
  def canonical_url
    request.original_url
 end  

 def meta_description
  if content_for?(:meta_description)
    content_for(:meta_description)
  elsif @service.is_a?(ActiveRecord::Relation)
    "A comprehensive list of our services." # Adjust this as needed for your context
  elsif @service&.meta_description.present?
    @service.meta_description
  elsif @page&.meta_description.present?
    @page.meta_description
  elsif @article&.meta_description.present?
    @article.meta_description
  else
    extract_description(@service&.content || @page&.content) || Setting.get('website-description')
  end
end 

  def unread_messages_count
    ContactMessage.unread_count
  end

  def favicon_url
    favicon = Setting.get('favicon')
    favicon.presence || asset_path('favicon.ico')
  end
  
  def twitter_card
    "summary_large_image" # Default to summary with a large image
  end

  def twitter_title
    og_title
  end

  def twitter_description
    og_description
  end

  def twitter_image
    og_image
  end

  def og_type
    if defined?(@article)
      "article"
    elsif defined?(@product)
      "product"
    else
      "website"
    end
  end

  def og_url
    request.original_url
  end

  def og_image
    if content_for?(:og_image)
      content_for(:og_image)
    else
      seo_image = url_for(Setting.get('seo-image'))

      if @service.is_a?(ActiveRecord::Relation)
        seo_image # Use a fallback image for the collection (e.g., a default list image)
      else
        service_image = @service&.images&.first
        page_image = @page&.images&.first

        if service_image.present?
          url_for(service_image)
        elsif page_image.present?
          url_for(page_image)
        else
          seo_image
        end
      end
    end
  end

  def og_description
    meta_description
  end

  def og_title
    meta_title
  end

  def meta_keywords
    if content_for?(:meta_keywords)
      content_for(:meta_keywords)
    elsif @service.is_a?(ActiveRecord::Relation)
      "services, list, offerings" # Adjust this as needed for your context
    elsif @service&.meta_keywords.present?
      @service.meta_keywords
    elsif @page&.meta_keywords.present?
      @page.meta_keywords
    elsif @article&.meta_keywords.present?
      @article.meta_keywords
    else
      extract_keywords(@service&.content || @page&.content) || @article&.content || Setting.get('default-keywords')
    end
  end
      
  def sub_menu_open_controllers
    %w[home acct_mgmt content pages economy]
  end
  
  def sub_menu_open?
    sub_menu_open_controllers.include?(controller.controller_name)
  end

  private

  def extract_description(content)
    content.to_plain_text.truncate(160) if content.present?
  end

  def extract_keywords(content)
    return "" unless content.present?
    # Extract keywords from the content (simple implementation)
    keywords = strip_tags(content).split.uniq.take(10).join(", ")
    keywords.presence || "default, keywords, for, your, website"
  end

  def page_url(page)
    "/#{page.slug}"
  end
end
