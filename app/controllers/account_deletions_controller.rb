class AccountDeletionsController < ApplicationController
  # `new` is a real screen rather than a browser dialog: the copy has to name
  # both the 30 days and the permanence, which is more than a confirm box can
  # carry.
  def new
  end

  def create
    Current.user.delete_account!
    cookies.delete(:session_id)
    redirect_to new_session_path,
                notice: "Sua conta foi excluída. Você tem 30 dias para voltar atrás entrando de novo."
  end
end
