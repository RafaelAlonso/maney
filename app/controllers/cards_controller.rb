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
    @card.card_schedules.build(closing_day: card_params[:closing_day], due_day: card_params[:due_day],
                               valid_from: Setting.instance.first_month)
    if @card.save
      redirect_to cards_path, notice: "Cartão cadastrado."
    else
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
    if [@card, *schedule].all?(&:valid?)
      ActiveRecord::Base.transaction { @card.save!; schedule&.save! }
      redirect_to cards_path, notice: "Cartão atualizado."
    else
      @card.errors.merge!(schedule.errors) if schedule
      # `reschedule` pode ter sujado uma linha dentro da associação
      # `card_schedules` já carregada; recarrega para o form e a lista não
      # mostrarem dias que não foram de fato salvos.
      @card.reload
      @card.name = card_params[:name]
      @days = card_params.slice(:closing_day, :due_day)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @card.expenses.exists? || @card.installment_purchases.exists?
      redirect_to new_card_migration_path(@card)
    else
      @card.destroy
      redirect_to cards_path, notice: "Cartão excluído."
    end
  end

  private

  def set_card = @card = Card.find(params[:id])

  def card_params = params.require(:card).permit(:name, :closing_day, :due_day)
end
