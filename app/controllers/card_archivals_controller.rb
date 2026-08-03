# Archiving lives apart from CardsController on purpose: that controller is
# entirely about the name and the closing/due days, including the confirmation
# screen for a days change that moves due dates. Archiving shares none of it and
# can never be refused — a cancelled card usually still owes, and blocking it
# then would defeat the point.
class CardArchivalsController < ApplicationController
  before_action :set_card

  def create
    @card.archive!
    redirect_to cards_path, notice: "Cartão arquivado."
  end

  def destroy
    @card.reactivate!
    redirect_to cards_path, notice: "Cartão reativado."
  end

  private

  def set_card = @card = Card.find(params[:card_id])
end
