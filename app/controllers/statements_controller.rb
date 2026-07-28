# Read-only screens over the derived statements. There is no cards#show: the
# statement list IS the card's page, and nothing else would live on a separate
# one today.
class StatementsController < ApplicationController
  before_action :set_card

  def index
    @card_statements = Budgeting::CardStatements.new(card: @card)
    @schedule = Budgeting::Schedule.for(card: @card, date: Date.current)
  end

  private

  def set_card = @card = Card.find(params[:card_id])
end
