module PeopleHelper
  def invitation_status(invitation)
    invitation.expired? ? "expirado" : "pendente"
  end

  def person_status(user)
    return "excluída" if user.deleted?
    return "acesso encerrado" if user.access_revoked?

    "ativa"
  end

  def delivery_status(invitation)
    { "sending" => "enviando", "sent" => "enviado", "failed" => "não enviado" }.fetch(invitation.delivery_state)
  end
end
