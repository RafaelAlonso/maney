module Invitations
  # Sends an invitation and records whether it went out.
  #
  # It rescues on purpose. A background job that raises tells Rafael nothing —
  # and the story is explicit that a failed send must not leave someone pending
  # forever. Writing `failed` on the row is what surfaces "não enviado" and the
  # Reenviar button on his list.
  class DeliveryJob < ApplicationJob
    def perform(invitation, token)
      InvitationMailer.invite(invitation, token).deliver_now
      invitation.update!(delivery_state: "sent")
    rescue StandardError => error
      invitation.update!(delivery_state: "failed")
      Rails.logger.error("Invitation #{invitation.id} could not be sent: #{error.class}: #{error.message}")
    end
  end
end
