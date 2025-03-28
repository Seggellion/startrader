class StarBitizenRunsController < ApplicationController
  before_action :set_shard
  before_action :prepend_theme_view_path

  def shard_index
    @star_bitizen_runs = StarBitizenRun.where(shard: @shard.name).order(created_at: :desc)

    # Look for custom themed template, fall back if needed
    theme_template_path = "layouts/shard_index"
    fallback_template   = "layouts/shard_index"

    if lookup_context.exists?(theme_template_path, [], false)
      render theme_template_path
    else
      render fallback_template
    end
  end

  private

  def set_shard
    @shard = Shard.find_by!(name: params[:name])
  end

  def prepend_theme_view_path
    theme_path = Rails.root.join("app", "themes", current_theme, "views")
    prepend_view_path theme_path
  end

  def current_theme
    # This can be dynamic if needed — for now, hardcoded as "Dusk"
    "Dusk"
  end
end
