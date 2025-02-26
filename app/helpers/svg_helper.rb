module SvgHelper
    def show_svg(icon_name, options={})
      file = File.read(Rails.root.join('app', 'themes', current_theme, 'assets', 'images', "#{icon_name}.svg"))
      doc = Nokogiri::HTML::DocumentFragment.parse file
      svg = doc.at_css 'svg'
  
      options.each {|attr, value| svg[attr.to_s] = value}
  
      doc.to_html.html_safe
    end
  end
  