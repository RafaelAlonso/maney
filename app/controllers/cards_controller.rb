class CardsController < ApplicationController
  before_action :set_card, only: %i[edit update destroy]

  def index
    @cards = Card.order(:name)
  end

  def new
    @card = Card.new
    @days = {}
  end

  def create
    @card = Card.new(name: card_params[:name])
    schedule = @card.card_schedules.build(closing_day: card_params[:closing_day], due_day: card_params[:due_day],
                                          valid_from: Setting.instance.first_month)
    if @card.save
      redirect_to cards_path, notice: "Cartão cadastrado."
    else
      # `@card.save` invalidates the child schedule as a side effect of the
      # autosave and leaves only the generic "Card schedules is invalid" in
      # @card.errors — the specific message ("Closing day is not included in
      # the list") stays isolated in `schedule.errors`. Merge so the user sees
      # the cause and drop the generic one, which adds nothing after that.
      @card.errors.merge!(schedule.errors)
      @card.errors.delete(:card_schedules)
      @days = card_params.slice(:closing_day, :due_day)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    schedule = Budgeting::Schedule.for(card: @card, date: Date.current)
    @days = { closing_day: schedule.closing_day, due_day: schedule.due_day }
  end

  def update
    @card.name = card_params[:name]
    schedule = @card.reschedule(closing_day: card_params[:closing_day], due_day: card_params[:due_day])
    # Don't use `[@card, *schedule].all?(&:valid?)`: `Enumerable#all?`
    # short-circuits, so if @card is already invalid `schedule.valid?` never
    # runs. This goes unnoticed when `schedule` is a new row (the autosave of
    # `@card.valid?` validates the unsaved children as a side effect), but
    # `reschedule` can return an already-persisted, dirty row (see
    # Card#reschedule) — for that one, autosave doesn't validate without
    # `autosave: true`. Call both `valid?` always, without relying on
    # short-circuiting or on that side effect.
    card_valid = @card.valid?
    schedule_valid = schedule.nil? || schedule.valid?
    if card_valid && schedule_valid
      ActiveRecord::Base.transaction { @card.save!; schedule&.save! }
      redirect_to cards_path, notice: "Cartão atualizado."
    else
      @card.errors.merge!(schedule.errors) if schedule
      # Same reason as `create`: when the row is new, the autosave of
      # `@card.valid?` plants the generic "Card schedules is invalid" next to
      # the specific message. One cause at a time.
      @card.errors.delete(:card_schedules)
      # `reschedule` may have dirtied a row inside the already-loaded
      # `card_schedules` association; reload so the form and the list don't show
      # days that weren't actually saved.
      @card.reload
      @card.name = card_params[:name]
      @days = card_params.slice(:closing_day, :due_day)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @card.expenses.exists? || @card.installment_purchases.exists?
      redirect_to new_card_migration_path(@card)
    elsif @card.destroy
      redirect_to cards_path, notice: "Cartão excluído."
    else
      # Unreachable today through the guard above (which is complete against the
      # current model), but `dependent: :restrict_with_error` makes `destroy`
      # return `false` instead of raising — without this branch, a real failure
      # would announce success while the record still exists.
      redirect_to cards_path, alert: @card.errors.full_messages.to_sentence
    end
  end

  private

  def set_card = @card = Card.find(params[:id])

  def card_params = params.require(:card).permit(:name, :closing_day, :due_day)
end
