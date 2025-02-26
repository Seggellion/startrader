# config/sitemap.rb
SitemapGenerator::Sitemap.default_host = "https://www.star_trader.com"

SitemapGenerator::Sitemap.create do
  add root_path, priority: 1.0, changefreq: 'daily'
  
  Service.find_each do |service|
    add service_path(service), lastmod: service.updated_at
  end

  # Add UpdateCenter pages
  add update_center_path, priority: 0.9, changefreq: 'weekly'
  add update_center_fyi_path, priority: 0.8, changefreq: 'monthly'

  Post.find_each do |post|
    add post_path(post), lastmod: post.updated_at
  end

  Page.find_each do |page|
    add catch_all_page_path(page.slug), lastmod: page.updated_at
  end
end
