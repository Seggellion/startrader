module SectionsHelper
    def render_section(section)
      render partial: "sections/#{section.template}", locals: { section: section }
    end
  end
  