class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_setup
  before_action :canonicalize_month
  helper_method :current_month, :month_param, :default_entry_date

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

  # Rafael is the sole inviter by decision. This raises rather than rendering a
  # forbidden page: AC 8 asks that no way to invite *exists* for anyone else,
  # and a 403 is a way of existing. The existing RecordNotFound handler turns
  # this into the app's ordinary "this record is gone" message.
  def require_admin
    raise ActiveRecord::RecordNotFound unless Current.user&.admin?
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

  # The month in context, in the form every `?month=` and redirect uses.
  def month_param = current_month.strftime("%Y-%m")

  # The date a new entry's form starts on. Handing the user *today* while they
  # are working in another month (closing March in July) is how an entry lands
  # in the wrong month behind a form that looked right — so outside the current
  # month the form starts on the 1st of the month on screen, which the user then
  # corrects to the real day.
  def default_entry_date
    today = Date.current
    current_month == today.beginning_of_month ? today : current_month
  end

  # `current_month` silently repairs a `?month=` that is unparseable or before
  # the first month, so the page is right but the address bar keeps claiming a
  # month the screen doesn't show — a bookmarked or shared link then names a
  # month it doesn't open. Send the browser to the month actually rendered.
  # Deterministic, so it can't loop: the redirect target already satisfies the
  # guard.
  def canonicalize_month
    return unless request.get? && params[:month].present?
    return if params[:month] == month_param

    redirect_to "#{request.path}?#{request.query_parameters.merge('month' => month_param).to_query}"
  end
end
