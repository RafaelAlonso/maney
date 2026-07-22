class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_setup
  helper_method :current_month

  # Qualquer `find` (Expense, Card, ...) pode receber um id obsoleto — um
  # link que ficou aberto em outra aba, ou voltou pelo histórico, para um
  # registro que já não existe. Sem isso, `Model.find` levantaria e a tela
  # quebraria com um 500 cru. A mensagem aqui é deliberadamente neutra: o
  # motivo de um id ficar obsoleto varia por controller (ver
  # `ExpensesController#record_not_found` para o caso das parcelas), e este
  # handler é herdado por todos eles — dar aqui uma explicação específica de
  # um controller contaria uma mentira nos outros.
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
