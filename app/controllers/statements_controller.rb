# Read-only screens over the derived statements. There is no cards#show: the
# statement list IS the card's page, and nothing else would live on a separate
# one today.
class StatementsController < ApplicationController
  before_action :set_card

  def index
    @card_statements = Budgeting::CardStatements.new(card: @card)
    @schedule = Budgeting::Schedule.for(card: @card, date: Date.current)
  end

  # A statement exists only where its expenses do, so the last expense leaving it
  # (an edited date moving it to the next statement, a deletion) makes the URL
  # stop resolving. Bouncing the user to the home screen of a different month for
  # a link that was valid a moment ago is the wrong answer — the same courtesy
  # w3 AC4 gives a card with no statements is given here: an empty state that
  # says what happened and links back to the card. Only a malformed id is still
  # a stale link (see `nominal_closing`).
  def show
    @nominal_closing = nominal_closing
    @row = Budgeting::CardStatements.new(card: @card).find(@nominal_closing)
    render :empty if @row.nil?
  end

  private

  def set_card = @card = Card.find(params[:card_id])

  # The id is a statement's nominal closing date. A malformed id and an id that
  # no longer resolves (the expense was deleted, or a schedule edit moved the
  # boundary) are the same kind of stale link, so both end in the neutral
  # redirect inherited from ApplicationController — never a 500. No
  # controller-specific message here: unlike ExpensesController's installment
  # case, there is no particular explanation to give.
  def nominal_closing
    Date.iso8601(params[:id])
  rescue Date::Error
    raise ActiveRecord::RecordNotFound
  end
end
