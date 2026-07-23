class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_setup
  helper_method :current_month

  # Any `find` (Expense, Card, ...) can receive a stale id — a link left open in
  # another tab, or reached via the back button, pointing at a record that no
  # longer exists. Without this, `Model.find` would raise and the screen would
  # break with a raw 500. The message here is deliberately neutral: the reason an
  # id goes stale varies by controller (see `ExpensesController#record_not_found`
  # for the installment case), and this handler is inherited by all of them —
  # giving a controller-specific explanation here would tell a lie in the others.
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

  def require_setup
    redirect_to setup_path if Setting.instance.nil?
  end

  def record_not_found
    redirect_to root_path, alert: "Este registro não existe mais."
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
