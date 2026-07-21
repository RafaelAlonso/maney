class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_setup
  helper_method :current_month

  private

  def require_setup
    redirect_to setup_path if Setting.instance.nil?
  end

  def current_month
    @current_month ||= begin
      month = begin
        Date.strptime(params[:month].to_s, "%Y-%m")
      rescue ArgumentError
        Date.current
      end.beginning_of_month
      first = Setting.instance&.first_month
      first && month < first ? first : month
    end
  end
end
